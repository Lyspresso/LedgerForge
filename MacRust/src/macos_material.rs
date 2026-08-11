//! Small, public-AppKit-only bridge for native macOS window materials.
//!
//! `NSVisualEffectView` provides the structural backdrop on every macOS version
//! LedgerForge supports. On macOS 26 and newer, documented `NSGlassEffectView`
//! instances provide Liquid Glass under the floating toolbar groups. We avoid
//! undocumented material values and selectors entirely.

use std::ffi::CStr;
use std::fmt;

use objc2::rc::Retained;
use objc2::runtime::AnyClass;
use objc2::{MainThreadMarker, Message};
use objc2_app_kit::{
    NSAutoresizingMaskOptions, NSGlassEffectContainerView, NSGlassEffectView,
    NSGlassEffectViewStyle, NSView, NSVisualEffectBlendingMode, NSVisualEffectMaterial,
    NSVisualEffectState, NSVisualEffectView, NSWindowOrderingMode, NSWorkspace,
};
use objc2_foundation::{NSPoint, NSRect, NSSize};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};

use crate::desktop::TOOLBAR_GLASS_REGION_COUNT;

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

/// Owns native material views for the lifetime of the eframe window.
#[derive(Debug)]
pub struct SystemMaterial {
    renderer_view: Retained<NSView>,
    _container: Retained<NSView>,
    _backdrop: Retained<NSVisualEffectView>,
    glass_container: Option<Retained<NSGlassEffectContainerView>>,
    glass_content: Option<Retained<NSView>>,
    glass_views: Vec<Retained<NSGlassEffectView>>,
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

    let (glass_container, glass_content, glass_views) = if liquid_glass_classes_are_available() {
        let batch =
            NSGlassEffectContainerView::initWithFrame(main_thread.alloc(), root_view.frame());
        batch.setAutoresizingMask(
            NSAutoresizingMaskOptions::ViewWidthSizable
                | NSAutoresizingMaskOptions::ViewHeightSizable,
        );
        batch.setSpacing(0.0);
        let content = NSView::initWithFrame(main_thread.alloc(), batch.bounds());
        content.setAutoresizingMask(
            NSAutoresizingMaskOptions::ViewWidthSizable
                | NSAutoresizingMaskOptions::ViewHeightSizable,
        );
        batch.setContentView(Some(&content));

        let views = (0..TOOLBAR_GLASS_REGION_COUNT)
            .map(|_| {
                let glass = NSGlassEffectView::initWithFrame(
                    main_thread.alloc(),
                    NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(0.0, 0.0)),
                );
                glass.setStyle(NSGlassEffectViewStyle::Regular);
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
        batch.setHidden(true);
        container.addSubview_positioned_relativeTo(
            &batch,
            NSWindowOrderingMode::Above,
            Some(&effect_view),
        );
        (Some(batch), Some(content), views)
    } else {
        (None, None, Vec::new())
    };

    Ok(SystemMaterial {
        renderer_view: root_view.retain(),
        _container: container,
        _backdrop: effect_view,
        glass_container,
        glass_content,
        glass_views,
    })
}

impl SystemMaterial {
    /// Whether this runtime provides Apple's public macOS 26 Liquid Glass view.
    pub fn liquid_glass_available(&self) -> bool {
        self.glass_container.is_some()
            && self.glass_content.is_some()
            && self.glass_views.len() == TOOLBAR_GLASS_REGION_COUNT
    }

    /// Whether Liquid Glass should currently be presented for this user.
    pub fn liquid_glass_visible(&self) -> bool {
        self.liquid_glass_available() && !reduce_transparency_is_enabled()
    }

    /// Updates native glass geometry after egui has laid out the toolbar.
    ///
    /// Returns `true` when glass is visible. Reduce Transparency hides the glass
    /// while retaining the stable `NSVisualEffectView` fallback.
    pub fn update_toolbar_glass(
        &self,
        regions: [Option<GlassRect>; TOOLBAR_GLASS_REGION_COUNT],
        viewport_width: f32,
        viewport_height: f32,
    ) -> bool {
        let visible = self.liquid_glass_visible();
        let Some(batch) = &self.glass_container else {
            return false;
        };
        let Some(glass_content) = &self.glass_content else {
            return false;
        };
        batch.setHidden(!visible);
        if !visible || viewport_width <= 0.0 || viewport_height <= 0.0 {
            return false;
        }

        let bounds = self.renderer_view.bounds();
        let scale_x = bounds.size.width / f64::from(viewport_width);
        let scale_y = bounds.size.height / f64::from(viewport_height);

        for (view, region) in self.glass_views.iter().zip(regions) {
            let Some(region) = region else {
                view.setHidden(true);
                continue;
            };
            let native_rect = self.app_kit_rect(region, scale_x, scale_y, glass_content);
            view.setCornerRadius(native_rect.size.height / 2.0);
            view.setFrame(native_rect);
            view.setHidden(false);
        }

        visible
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

fn reduce_transparency_is_enabled() -> bool {
    if MainThreadMarker::new().is_none() {
        return true;
    }
    NSWorkspace::sharedWorkspace().accessibilityDisplayShouldReduceTransparency()
}

#[cfg(test)]
mod tests {
    use super::{GlassRect, renderer_space_rect};
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
}
