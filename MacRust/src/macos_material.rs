//! Small, public-AppKit-only bridge for native macOS window materials.
//!
//! `NSVisualEffectView` provides semantic structural materials on every macOS
//! version LedgerForge supports. On macOS 26 and newer, documented
//! `NSGlassEffectView` instances provide Liquid Glass under the floating toolbar,
//! navigation sidebar, and inspector. We avoid undocumented material values and
//! selectors entirely.

use std::ffi::CStr;
use std::fmt;

use objc2::rc::Retained;
use objc2::runtime::AnyClass;
use objc2::{MainThreadMarker, Message};
use objc2_app_kit::{
    NSAutoresizingMaskOptions, NSColor, NSGlassEffectContainerView, NSGlassEffectView,
    NSGlassEffectViewStyle, NSToolbar, NSToolbarDisplayMode, NSView, NSVisualEffectBlendingMode,
    NSVisualEffectMaterial, NSVisualEffectState, NSVisualEffectView, NSWindowOrderingMode,
    NSWindowToolbarStyle, NSWorkspace,
};
use objc2_foundation::{NSPoint, NSRect, NSSize};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};

use crate::desktop::{STRUCTURAL_GLASS_REGION_COUNT, TOOLBAR_GLASS_REGION_COUNT};

const LIBRARY_TINT_ALPHA: f64 = 0.30;
const INSPECTOR_TINT_ALPHA: f64 = 0.24;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlassRect {
    pub min_x: f64,
    pub min_y: f64,
    pub max_x: f64,
    pub max_y: f64,
}

impl GlassRect {
    pub fn new(min_x: f32, min_y: f32, max_x: f32, max_y: f32) -> Self {
        Self {
            min_x: f64::from(min_x),
            min_y: f64::from(min_y),
            max_x: f64::from(max_x),
            max_y: f64::from(max_y),
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct NativeMaterialState {
    pub liquid_glass_visible: bool,
    pub structural_material_visible: bool,
    pub reduce_transparency: bool,
    pub increased_contrast: bool,
}

#[derive(Debug)]
struct GlassBatch {
    container: Retained<NSGlassEffectContainerView>,
    content: Retained<NSView>,
    views: Vec<Retained<NSGlassEffectView>>,
}

/// Owns native material views for the lifetime of the eframe window.
#[derive(Debug)]
pub struct SystemMaterial {
    renderer_view: Retained<NSView>,
    _toolbar: Retained<NSToolbar>,
    _container: Retained<NSView>,
    _backdrop: Retained<NSVisualEffectView>,
    structural_fallback_views: Vec<Retained<NSVisualEffectView>>,
    toolbar_glass: Option<GlassBatch>,
    structural_glass: Option<GlassBatch>,
}

#[derive(Debug)]
pub enum MaterialError {
    WindowHandle(raw_window_handle::HandleError),
    UnsupportedWindow,
    NotMainThread,
}

impl fmt::Display for MaterialError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::WindowHandle(error) => error.fmt(formatter),
            Self::UnsupportedWindow => formatter.write_str("the window is not an AppKit window"),
            Self::NotMainThread => {
                formatter.write_str("the macOS material must be installed on the main thread")
            }
        }
    }
}

/// Installs the semantic backdrop and any runtime-supported Liquid Glass views.
pub fn install_system_material(
    window: &impl HasWindowHandle,
) -> Result<SystemMaterial, MaterialError> {
    let window_handle = window
        .window_handle()
        .map_err(MaterialError::WindowHandle)?;
    let RawWindowHandle::AppKit(handle) = window_handle.as_raw() else {
        return Err(MaterialError::UnsupportedWindow);
    };
    let main_thread = MainThreadMarker::new().ok_or(MaterialError::NotMainThread)?;

    // SAFETY: raw-window-handle guarantees that `ns_view` is a valid AppKit NSView
    // for the lifetime of the borrowed window handle. This function runs during
    // eframe creation on AppKit's main thread, before normal UI rendering begins.
    let root_view = unsafe { handle.ns_view.cast::<NSView>().as_ref() };

    // LedgerForge draws its controls in the full-size content view, but this is
    // still structurally a toolbar window. Giving AppKit an empty native toolbar
    // lets the system choose the toolbar-window corner radius and standard-button
    // insets for the current macOS release and titlebar layout direction. The
    // toolbar has no items, so hit testing continues through to egui's controls.
    let native_window = root_view.window().ok_or(MaterialError::UnsupportedWindow)?;
    let toolbar = native_window.toolbar().unwrap_or_else(|| {
        let toolbar = NSToolbar::init(main_thread.alloc());
        native_window.setToolbar(Some(&toolbar));
        toolbar
    });
    toolbar.setDisplayMode(NSToolbarDisplayMode::IconOnly);
    toolbar.setAllowsUserCustomization(false);
    toolbar.setAutosavesConfiguration(false);
    toolbar.setVisible(true);
    native_window.setToolbarStyle(NSWindowToolbarStyle::Unified);

    // `raw-window-handle` points at winit's renderer view. A subview would sit
    // above that view's own OpenGL layer, even when ordered below its siblings.
    // Put native materials in the parent and order them explicitly behind the
    // renderer, which remains the sole input surface.
    // SAFETY: AppKit view-hierarchy access happens on the main thread, and the
    // retained parent remains valid for this operation.
    let container = unsafe { root_view.superview() }.ok_or(MaterialError::UnsupportedWindow)?;
    let effect_view = NSVisualEffectView::initWithFrame(main_thread.alloc(), root_view.frame());
    effect_view.setMaterial(NSVisualEffectMaterial::UnderWindowBackground);
    effect_view.setBlendingMode(NSVisualEffectBlendingMode::BehindWindow);
    effect_view.setState(NSVisualEffectState::FollowsWindowActiveState);
    effect_view.setAutoresizingMask(
        NSAutoresizingMaskOptions::ViewWidthSizable | NSAutoresizingMaskOptions::ViewHeightSizable,
    );
    container.addSubview_positioned_relativeTo(
        &effect_view,
        NSWindowOrderingMode::Below,
        Some(root_view),
    );

    let structural_fallback_views = [
        NSVisualEffectMaterial::Sidebar,
        NSVisualEffectMaterial::ContentBackground,
    ]
    .into_iter()
    .map(|material| {
        let view = NSVisualEffectView::initWithFrame(main_thread.alloc(), zero_rect());
        view.setMaterial(material);
        view.setBlendingMode(NSVisualEffectBlendingMode::BehindWindow);
        view.setState(NSVisualEffectState::FollowsWindowActiveState);
        view.setHidden(true);
        container.addSubview_positioned_relativeTo(
            &view,
            NSWindowOrderingMode::Above,
            Some(&effect_view),
        );
        view
    })
    .collect();

    let (toolbar_glass, structural_glass) = if liquid_glass_classes_are_available() {
        let toolbar_batch = create_glass_batch(
            main_thread,
            root_view.frame(),
            TOOLBAR_GLASS_REGION_COUNT,
            &[],
        );
        let accent = NSColor::controlAccentColor();
        let structural_tints = [
            accent.colorWithAlphaComponent(LIBRARY_TINT_ALPHA),
            accent.colorWithAlphaComponent(INSPECTOR_TINT_ALPHA),
        ];
        let structural_batch = create_glass_batch(
            main_thread,
            root_view.frame(),
            STRUCTURAL_GLASS_REGION_COUNT,
            &structural_tints,
        );

        // Keep the structural panes and toolbar pills in distinct containers so
        // the system never merges a full-height pane into a nearby toolbar shape.
        for batch in [&structural_batch, &toolbar_batch] {
            container.addSubview_positioned_relativeTo(
                &batch.container,
                NSWindowOrderingMode::Below,
                Some(root_view),
            );
        }
        (Some(toolbar_batch), Some(structural_batch))
    } else {
        (None, None)
    };

    Ok(SystemMaterial {
        renderer_view: root_view.retain(),
        _toolbar: toolbar,
        _container: container,
        _backdrop: effect_view,
        structural_fallback_views,
        toolbar_glass,
        structural_glass,
    })
}

fn zero_rect() -> NSRect {
    NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(0.0, 0.0))
}

fn create_glass_batch(
    main_thread: MainThreadMarker,
    frame: NSRect,
    count: usize,
    tints: &[Retained<NSColor>],
) -> GlassBatch {
    let container = NSGlassEffectContainerView::initWithFrame(main_thread.alloc(), frame);
    container.setAutoresizingMask(
        NSAutoresizingMaskOptions::ViewWidthSizable | NSAutoresizingMaskOptions::ViewHeightSizable,
    );
    container.setSpacing(0.0);
    let content = NSView::initWithFrame(main_thread.alloc(), container.bounds());
    content.setAutoresizingMask(
        NSAutoresizingMaskOptions::ViewWidthSizable | NSAutoresizingMaskOptions::ViewHeightSizable,
    );
    container.setContentView(Some(&content));

    let views = (0..count)
        .map(|index| {
            let glass = NSGlassEffectView::initWithFrame(main_thread.alloc(), zero_rect());
            glass.setStyle(NSGlassEffectViewStyle::Regular);
            if let Some(tint) = tints.get(index) {
                glass.setTintColor(Some(tint));
            }
            glass.setCornerRadius(18.0);
            glass.setHidden(true);
            let foreground = NSView::initWithFrame(main_thread.alloc(), glass.bounds());
            foreground.setAutoresizingMask(
                NSAutoresizingMaskOptions::ViewWidthSizable
                    | NSAutoresizingMaskOptions::ViewHeightSizable,
            );
            glass.setContentView(Some(&foreground));
            content.addSubview(&glass);
            glass
        })
        .collect();
    container.setHidden(true);

    GlassBatch {
        container,
        content,
        views,
    }
}

impl SystemMaterial {
    /// Whether this runtime provides Apple's public macOS 26 Liquid Glass view.
    pub fn liquid_glass_available(&self) -> bool {
        self.toolbar_glass
            .as_ref()
            .is_some_and(|batch| batch.views.len() == TOOLBAR_GLASS_REGION_COUNT)
            && self
                .structural_glass
                .as_ref()
                .is_some_and(|batch| batch.views.len() == STRUCTURAL_GLASS_REGION_COUNT)
    }

    /// Current system accessibility and material availability state.
    pub fn current_state(&self) -> NativeMaterialState {
        let (reduce_transparency, increased_contrast) = accessibility_display_options();
        material_state(
            self.liquid_glass_available(),
            self.structural_fallback_views.len() == STRUCTURAL_GLASS_REGION_COUNT,
            reduce_transparency,
            increased_contrast,
        )
    }

    /// Updates native material geometry after egui has laid out the workspace.
    ///
    /// Reduce Transparency hides every native effect; callers then paint the
    /// panes with opaque semantic fallback colors. Older systems use retained
    /// `NSVisualEffectView` panes instead of attempting to call macOS 26 APIs.
    pub fn update_native_materials(
        &self,
        toolbar_regions: [Option<GlassRect>; TOOLBAR_GLASS_REGION_COUNT],
        structural_regions: [Option<GlassRect>; STRUCTURAL_GLASS_REGION_COUNT],
        viewport_width: f32,
        viewport_height: f32,
    ) -> NativeMaterialState {
        let state = self.current_state();
        let glass_visible = state.liquid_glass_visible;
        if let Some(batch) = &self.toolbar_glass {
            batch.container.setHidden(!glass_visible);
        }
        if let Some(batch) = &self.structural_glass {
            batch.container.setHidden(!glass_visible);
        }
        self._backdrop.setHidden(state.reduce_transparency);
        let fallback_visible = state.structural_material_visible && !glass_visible;
        for view in &self.structural_fallback_views {
            view.setHidden(!fallback_visible);
        }

        if viewport_width <= 0.0 || viewport_height <= 0.0 {
            self.hide_native_regions();
            return NativeMaterialState {
                reduce_transparency: state.reduce_transparency,
                increased_contrast: state.increased_contrast,
                ..NativeMaterialState::default()
            };
        }

        let bounds = self.renderer_view.bounds();
        let scale_x = bounds.size.width / f64::from(viewport_width);
        let scale_y = bounds.size.height / f64::from(viewport_height);

        if glass_visible {
            if let Some(batch) = &self.toolbar_glass {
                self.update_glass_batch(
                    batch,
                    &toolbar_regions,
                    scale_x,
                    scale_y,
                    toolbar_corner_radius,
                );
            }
            if let Some(batch) = &self.structural_glass {
                self.update_glass_batch(
                    batch,
                    &structural_regions,
                    scale_x,
                    scale_y,
                    structural_corner_radius,
                );
            }
        }

        if fallback_visible {
            for (view, region) in self
                .structural_fallback_views
                .iter()
                .zip(structural_regions)
            {
                let Some(region) = region else {
                    view.setHidden(true);
                    continue;
                };
                let native_rect = self.app_kit_rect(region, scale_x, scale_y, &self._container);
                view.setFrame(native_rect);
                view.setHidden(false);
            }
        }

        state
    }

    fn update_glass_batch(
        &self,
        batch: &GlassBatch,
        regions: &[Option<GlassRect>],
        scale_x: f64,
        scale_y: f64,
        corner_radius: fn(usize, f64) -> f64,
    ) {
        for (index, (view, region)) in batch.views.iter().zip(regions).enumerate() {
            let Some(region) = *region else {
                view.setHidden(true);
                continue;
            };
            let native_rect = self.app_kit_rect(region, scale_x, scale_y, &batch.content);
            view.setCornerRadius(corner_radius(index, native_rect.size.height));
            view.setFrame(native_rect);
            view.setHidden(false);
        }
    }

    fn hide_native_regions(&self) {
        for batch in [&self.toolbar_glass, &self.structural_glass]
            .into_iter()
            .flatten()
        {
            batch.container.setHidden(true);
            for view in &batch.views {
                view.setHidden(true);
            }
        }
        for view in &self.structural_fallback_views {
            view.setHidden(true);
        }
    }

    fn app_kit_rect(
        &self,
        rect: GlassRect,
        scale_x: f64,
        scale_y: f64,
        glass_content: &NSView,
    ) -> NSRect {
        let bounds = self.renderer_view.bounds();
        let renderer_rect = renderer_space_rect(
            rect,
            bounds,
            self.renderer_view.isFlipped(),
            scale_x,
            scale_y,
        );
        self.renderer_view
            .convertRect_toView(renderer_rect, Some(glass_content))
    }
}

fn toolbar_corner_radius(_index: usize, height: f64) -> f64 {
    height / 2.0
}

fn structural_corner_radius(index: usize, height: f64) -> f64 {
    if index == 0 {
        // The navigation sidebar floats as a pane; the inspector remains
        // edge-to-edge to reflect its closer relationship to edited content.
        18.0_f64.min(height / 2.0)
    } else {
        0.0
    }
}

fn renderer_space_rect(
    rect: GlassRect,
    bounds: NSRect,
    is_flipped: bool,
    scale_x: f64,
    scale_y: f64,
) -> NSRect {
    let width = (rect.max_x - rect.min_x).max(0.0) * scale_x;
    let height = (rect.max_y - rect.min_y).max(0.0) * scale_y;
    let x = bounds.origin.x + rect.min_x * scale_x;
    let y = if is_flipped {
        bounds.origin.y + rect.min_y * scale_y
    } else {
        bounds.origin.y + bounds.size.height - rect.max_y * scale_y
    };
    NSRect::new(NSPoint::new(x, y), NSSize::new(width, height))
}

fn liquid_glass_classes_are_available() -> bool {
    const VIEW_CLASS_NAME: &CStr = c"NSGlassEffectView";
    const CONTAINER_CLASS_NAME: &CStr = c"NSGlassEffectContainerView";
    AnyClass::get(VIEW_CLASS_NAME).is_some() && AnyClass::get(CONTAINER_CLASS_NAME).is_some()
}

fn accessibility_display_options() -> (bool, bool) {
    if MainThreadMarker::new().is_none() {
        return (true, true);
    }
    let workspace = NSWorkspace::sharedWorkspace();
    (
        workspace.accessibilityDisplayShouldReduceTransparency(),
        workspace.accessibilityDisplayShouldIncreaseContrast(),
    )
}

fn material_state(
    liquid_glass_available: bool,
    structural_fallback_available: bool,
    reduce_transparency: bool,
    increased_contrast: bool,
) -> NativeMaterialState {
    NativeMaterialState {
        liquid_glass_visible: liquid_glass_available && !reduce_transparency,
        structural_material_visible: structural_fallback_available && !reduce_transparency,
        reduce_transparency,
        increased_contrast,
    }
}

#[cfg(test)]
mod tests {
    use super::{GlassRect, renderer_space_rect, structural_corner_radius, toolbar_corner_radius};
    use objc2_foundation::{NSPoint, NSRect, NSSize};

    #[test]
    fn glass_rect_scales_and_converts_both_coordinate_directions() {
        let rect = GlassRect::new(10.0, 20.0, 48.0, 58.0);
        let bounds = NSRect::new(NSPoint::new(3.0, 4.0), NSSize::new(1_180.0, 760.0));

        let app_kit = renderer_space_rect(rect, bounds, false, 1.25, 1.5);
        assert_eq!(app_kit.origin.x, 15.5);
        assert_eq!(app_kit.origin.y, 677.0);
        assert_eq!(app_kit.size.width, 47.5);
        assert_eq!(app_kit.size.height, 57.0);

        let flipped = renderer_space_rect(rect, bounds, true, 1.25, 1.5);
        assert_eq!(flipped.origin.x, 15.5);
        assert_eq!(flipped.origin.y, 34.0);
    }

    #[test]
    fn structural_glass_uses_sidebar_and_inspector_shapes() {
        assert_eq!(toolbar_corner_radius(0, 38.0), 19.0);
        assert_eq!(structural_corner_radius(0, 600.0), 18.0);
        assert_eq!(structural_corner_radius(1, 600.0), 0.0);
    }

    #[test]
    fn accessibility_material_state_uses_solid_reduce_transparency_fallback() {
        let normal = super::material_state(true, true, false, false);
        assert!(normal.liquid_glass_visible);
        assert!(normal.structural_material_visible);
        assert!(!normal.reduce_transparency);
        assert!(!normal.increased_contrast);

        let reduced = super::material_state(true, true, true, true);
        assert!(!reduced.liquid_glass_visible);
        assert!(!reduced.structural_material_visible);
        assert!(reduced.reduce_transparency);
        assert!(reduced.increased_contrast);

        let legacy = super::material_state(false, true, false, false);
        assert!(!legacy.liquid_glass_visible);
        assert!(legacy.structural_material_visible);
        assert!(!legacy.reduce_transparency);
    }
}
