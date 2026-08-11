//! Small, public-AppKit-only bridge for native macOS window materials.
//!
//! Pane-shaped `NSVisualEffectView` instances use behind-window blending so the
//! library and inspector visibly react to the desktop and other apps on every
//! macOS version LedgerForge supports. On macOS 26 and newer, documented
//! `NSGlassEffectView` instances provide Liquid Glass under the floating toolbar.
//! We avoid undocumented material values and selectors entirely.

use std::cell::{Cell, RefCell};
use std::collections::VecDeque;
use std::ffi::CStr;
use std::fmt;
use std::ptr::{NonNull, null_mut};
use std::rc::Rc;
use std::time::{Duration, Instant};

use block2::RcBlock;
use objc2::rc::Retained;
use objc2::runtime::{AnyClass, AnyObject};
use objc2::{MainThreadMarker, Message};
use objc2_app_kit::{
    NSAutoresizingMaskOptions, NSColor, NSEvent, NSEventMask, NSEventType,
    NSGlassEffectContainerView, NSGlassEffectView, NSGlassEffectViewStyle, NSToolbar,
    NSToolbarDisplayMode, NSView, NSVisualEffectBlendingMode, NSVisualEffectMaterial,
    NSVisualEffectState, NSVisualEffectView, NSWindowOrderingMode, NSWindowToolbarStyle,
    NSWorkspace,
};
use objc2_foundation::{NSPoint, NSRect, NSSize};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};

use crate::desktop::{STRUCTURAL_MATERIAL_REGION_COUNT, TOOLBAR_GLASS_REGION_COUNT};

const ACCESSIBILITY_POLL_INTERVAL: Duration = Duration::from_secs(1);

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

#[derive(Debug, Default)]
struct NativeNavigationState {
    button_rects: RefCell<[Option<NSRect>; 2]>,
    pending: RefCell<VecDeque<isize>>,
    press_active: Cell<bool>,
}

impl NativeNavigationState {
    fn begin_press(&self, delta: isize) -> bool {
        if self.press_active.replace(true) {
            return false;
        }
        self.pending.borrow_mut().push_back(delta);
        true
    }

    fn end_press(&self) {
        self.press_active.set(false);
    }
}

/// Owns native material views for the lifetime of the eframe window.
#[derive(Debug)]
pub struct SystemMaterial {
    renderer_view: Retained<NSView>,
    _toolbar: Retained<NSToolbar>,
    _container: Retained<NSView>,
    _backdrop: Retained<NSVisualEffectView>,
    structural_material_views: Vec<Retained<NSVisualEffectView>>,
    toolbar_glass: Option<GlassBatch>,
    navigation_state: Rc<NativeNavigationState>,
    navigation_monitor: Option<Retained<AnyObject>>,
    last_accessibility_poll: Option<Instant>,
    cached_state: NativeMaterialState,
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
    egui_context: &eframe::egui::Context,
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
    native_window.setOpaque(false);
    native_window.setBackgroundColor(Some(&NSColor::clearColor()));
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

    let structural_material_views = [
        NSVisualEffectMaterial::Sidebar,
        NSVisualEffectMaterial::UnderWindowBackground,
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

    let toolbar_glass = if liquid_glass_classes_are_available() {
        let batch = create_glass_batch(main_thread, root_view.frame(), TOOLBAR_GLASS_REGION_COUNT);
        container.addSubview_positioned_relativeTo(
            &batch.container,
            NSWindowOrderingMode::Below,
            Some(root_view),
        );
        Some(batch)
    } else {
        None
    };

    // Install the pre-dispatch monitor only after all fallible AppKit setup has
    // succeeded, so an early installation failure cannot leak a monitor token.
    let navigation_state = Rc::new(NativeNavigationState::default());
    let navigation_monitor = install_navigation_monitor(
        native_window.windowNumber(),
        Rc::clone(&navigation_state),
        egui_context.clone(),
    );

    Ok(SystemMaterial {
        renderer_view: root_view.retain(),
        _toolbar: toolbar,
        _container: container,
        _backdrop: effect_view,
        structural_material_views,
        toolbar_glass,
        navigation_state,
        navigation_monitor,
        last_accessibility_poll: None,
        cached_state: NativeMaterialState::default(),
    })
}

fn install_navigation_monitor(
    window_number: isize,
    navigation_state: Rc<NativeNavigationState>,
    egui_context: eframe::egui::Context,
) -> Option<Retained<AnyObject>> {
    let handler: RcBlock<dyn Fn(NonNull<NSEvent>) -> *mut NSEvent> =
        RcBlock::new(move |event_pointer: NonNull<NSEvent>| {
            // SAFETY: AppKit invokes a local-monitor block with a valid NSEvent
            // pointer for the duration of the call.
            let event = unsafe { event_pointer.as_ref() };
            if event.r#type() == NSEventType::LeftMouseUp {
                navigation_state.end_press();
                return event_pointer.as_ptr();
            }
            if event.windowNumber() != window_number {
                return event_pointer.as_ptr();
            }

            let location = event.locationInWindow();
            let delta =
                navigation_delta_at_point(location, *navigation_state.button_rects.borrow());
            let Some(delta) = delta else {
                return event_pointer.as_ptr();
            };

            // A physical click is one navigation action even if a synthetic
            // driver or unusual pointing device repeats mouse-down events while
            // the button remains held. The matching mouse-up re-arms the bridge.
            if !navigation_state.begin_press(delta) {
                return null_mut();
            }

            egui_context.request_repaint_of(eframe::egui::ViewportId::ROOT);

            // This physical arrow press is now represented by the queued native
            // command. Returning nil prevents AppKit/winit/egui from dispatching
            // the same mouse-down a second time; the unmatched mouse-up is safe
            // and preserves normal pointer/focus bookkeeping.
            null_mut()
        });

    // SAFETY: the handler returns either the event pointer supplied by AppKit or
    // null for a handled navigation press, exactly as the API contract requires.
    unsafe {
        NSEvent::addLocalMonitorForEventsMatchingMask_handler(
            NSEventMask::LeftMouseDown | NSEventMask::LeftMouseUp,
            &handler,
        )
    }
}

fn point_is_inside(point: NSPoint, rect: NSRect) -> bool {
    point.x >= rect.origin.x
        && point.y >= rect.origin.y
        && point.x < rect.origin.x + rect.size.width
        && point.y < rect.origin.y + rect.size.height
}

fn navigation_delta_at_point(point: NSPoint, button_rects: [Option<NSRect>; 2]) -> Option<isize> {
    button_rects.iter().enumerate().find_map(|(index, rect)| {
        rect.is_some_and(|rect| point_is_inside(point, rect))
            .then_some(if index == 0 { -1 } else { 1 })
    })
}

fn zero_rect() -> NSRect {
    NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(0.0, 0.0))
}

fn create_glass_batch(main_thread: MainThreadMarker, frame: NSRect, count: usize) -> GlassBatch {
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
        .map(|_| {
            let glass = NSGlassEffectView::initWithFrame(main_thread.alloc(), zero_rect());
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
    }

    /// Current system accessibility and material availability state.
    pub fn current_state(&mut self) -> NativeMaterialState {
        if self
            .last_accessibility_poll
            .is_some_and(|last_poll| last_poll.elapsed() < ACCESSIBILITY_POLL_INTERVAL)
        {
            return self.cached_state;
        }
        let (reduce_transparency, increased_contrast) = accessibility_display_options();
        self.cached_state = material_state(
            self.liquid_glass_available(),
            self.structural_material_views.len() == STRUCTURAL_MATERIAL_REGION_COUNT,
            reduce_transparency,
            increased_contrast,
        );
        self.last_accessibility_poll = Some(Instant::now());
        self.cached_state
    }

    /// Drains physical toolbar-arrow presses captured before AppKit dispatches
    /// them into titlebar tracking or winit's event translation.
    pub fn drain_navigation_commands(&self) -> Vec<isize> {
        self.navigation_state
            .pending
            .borrow_mut()
            .drain(..)
            .collect()
    }

    /// Updates native material geometry after egui has laid out the workspace.
    ///
    /// Reduce Transparency hides every native effect; callers then paint the
    /// panes with opaque semantic fallback colors. Structural panes use
    /// behind-window `NSVisualEffectView` on every supported macOS version.
    pub fn update_native_materials(
        &mut self,
        toolbar_regions: [Option<GlassRect>; TOOLBAR_GLASS_REGION_COUNT],
        structural_regions: [Option<GlassRect>; STRUCTURAL_MATERIAL_REGION_COUNT],
        navigation_regions: [Option<GlassRect>; 2],
        viewport_width: f32,
        viewport_height: f32,
        state: NativeMaterialState,
    ) -> NativeMaterialState {
        let bounds = self.renderer_view.bounds();
        // AppKit can rebuild titlebar material views while a unified toolbar
        // settles, the window changes key state, or it returns from fullscreen.
        // Keep these native effects synchronized on every rendered frame. A
        // geometry-only cache freezes behind-window sampling and can leave the
        // otherwise-transparent egui panes looking like flat fixed fills.
        let glass_visible = state.liquid_glass_visible;
        if let Some(batch) = &self.toolbar_glass {
            batch.container.setHidden(!glass_visible);
        }
        self._backdrop.setHidden(state.reduce_transparency);
        let structural_visible = state.structural_material_visible;
        for view in &self.structural_material_views {
            view.setHidden(!structural_visible);
        }

        if viewport_width <= 0.0 || viewport_height <= 0.0 {
            *self.navigation_state.button_rects.borrow_mut() = [None; 2];
            self.hide_native_regions();
            return NativeMaterialState {
                reduce_transparency: state.reduce_transparency,
                increased_contrast: state.increased_contrast,
                ..NativeMaterialState::default()
            };
        }

        let scale_x = bounds.size.width / f64::from(viewport_width);
        let scale_y = bounds.size.height / f64::from(viewport_height);
        *self.navigation_state.button_rects.borrow_mut() = navigation_regions.map(|region| {
            region.map(|region| {
                let renderer_rect = renderer_space_rect(
                    region,
                    bounds,
                    self.renderer_view.isFlipped(),
                    scale_x,
                    scale_y,
                );
                self.renderer_view.convertRect_toView(renderer_rect, None)
            })
        });

        if glass_visible && let Some(batch) = &self.toolbar_glass {
            self.update_glass_batch(
                batch,
                &toolbar_regions,
                scale_x,
                scale_y,
                toolbar_corner_radius,
            );
        }

        if structural_visible {
            for (view, region) in self
                .structural_material_views
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
        for batch in [&self.toolbar_glass].into_iter().flatten() {
            batch.container.setHidden(true);
            for view in &batch.views {
                view.setHidden(true);
            }
        }
        for view in &self.structural_material_views {
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

impl Drop for SystemMaterial {
    fn drop(&mut self) {
        if let Some(monitor) = self.navigation_monitor.take() {
            // SAFETY: this is the exact token returned by AppKit when the local
            // event monitor was installed, and eframe drops the app on the main
            // AppKit thread.
            unsafe { NSEvent::removeMonitor(&monitor) };
        }
    }
}

fn toolbar_corner_radius(_index: usize, height: f64) -> f64 {
    height / 2.0
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
    structural_material_available: bool,
    reduce_transparency: bool,
    increased_contrast: bool,
) -> NativeMaterialState {
    NativeMaterialState {
        liquid_glass_visible: liquid_glass_available && !reduce_transparency,
        structural_material_visible: structural_material_available && !reduce_transparency,
        reduce_transparency,
        increased_contrast,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        GlassRect, NativeNavigationState, navigation_delta_at_point, renderer_space_rect,
        toolbar_corner_radius,
    };
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
    fn toolbar_glass_uses_capsule_shapes() {
        assert_eq!(toolbar_corner_radius(0, 38.0), 19.0);
    }

    #[test]
    fn native_navigation_hit_test_distinguishes_both_arrows_and_background() {
        let previous = NSRect::new(NSPoint::new(110.0, 700.0), NSSize::new(32.0, 32.0));
        let next = NSRect::new(NSPoint::new(142.0, 700.0), NSSize::new(32.0, 32.0));
        let regions = [Some(previous), Some(next)];

        assert_eq!(
            navigation_delta_at_point(NSPoint::new(126.0, 716.0), regions),
            Some(-1)
        );
        assert_eq!(
            navigation_delta_at_point(NSPoint::new(158.0, 716.0), regions),
            Some(1)
        );
        assert_eq!(
            navigation_delta_at_point(NSPoint::new(142.0, 716.0), regions),
            Some(1),
            "the shared edge belongs to the next button"
        );
        assert_eq!(
            navigation_delta_at_point(NSPoint::new(180.0, 716.0), regions),
            None
        );
    }

    #[test]
    fn native_navigation_enqueues_once_until_mouse_up() {
        let state = NativeNavigationState::default();

        assert!(state.begin_press(1));
        assert!(!state.begin_press(1));
        assert_eq!(
            state.pending.borrow_mut().drain(..).collect::<Vec<_>>(),
            [1]
        );

        state.end_press();
        assert!(state.begin_press(-1));
        assert_eq!(
            state.pending.borrow_mut().drain(..).collect::<Vec<_>>(),
            [-1]
        );
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
