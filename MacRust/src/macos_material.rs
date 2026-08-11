//! Small, public-AppKit-only bridge for the native macOS window material.
//!
//! `NSVisualEffectView` is available on every macOS version LedgerForge supports.
//! We deliberately avoid undocumented material values and selectors. Liquid Glass
//! is handled by the system where native window chrome is used; the egui content
//! gets the stable semantic `UnderWindowBackground` material as its backdrop.

use std::fmt;

use objc2::MainThreadMarker;
use objc2_app_kit::{
    NSAutoresizingMaskOptions, NSView, NSVisualEffectBlendingMode, NSVisualEffectMaterial,
    NSVisualEffectState, NSVisualEffectView, NSWindowOrderingMode,
};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};

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

/// Installs a semantic AppKit backdrop behind the renderer's native content view.
///
/// AppKit retains the effect view after `addSubview`, so the local retained object
/// may be released once configuration is complete.
pub fn install_system_backdrop(window: &impl HasWindowHandle) -> Result<(), MaterialError> {
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
    // Put the material in the parent and order it explicitly behind the renderer.
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
    Ok(())
}
