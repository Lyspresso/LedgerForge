mod desktop;
#[cfg(target_os = "macos")]
mod macos_material;

fn main() -> eframe::Result {
    desktop::run()
}
