use std::collections::HashSet;
use std::path::PathBuf;
use std::time::Duration;

use accounting_question_core::{
    APP_IDENTIFIER, AccountingQuestion, CellValue, GradeResult, GradeStatus, LibraryQuestion,
    PartGrade, QuestionFormat, QuestionPart, QuestionProgress, QuestionShell, ResponseKind,
    StudentAnswer, StudioModel, evaluate_formula, evaluate_grid,
};
use eframe::egui::{
    self, Align, Button, Color32, ComboBox, CornerRadius, FontData, FontDefinitions, FontFamily,
    FontId, Frame, Grid, KeyboardShortcut, Label, Layout, Margin, Modifiers, Panel, ProgressBar,
    RichText, ScrollArea, Sense, Shadow, Stroke, TextEdit, TextStyle, Theme, ThemePreference,
    UiBuilder, Vec2, WidgetInfo, WidgetType,
};
#[cfg(target_os = "macos")]
use raw_window_handle::HasWindowHandle as _;

const APP_TITLE: &str = "LedgerForge — Accounting Question Studio";
pub(crate) const TOOLBAR_GLASS_REGION_COUNT: usize = 4;

#[derive(Debug, Clone, Copy)]
struct Palette {
    canvas: Color32,
    sidebar: Color32,
    toolbar: Color32,
    card: Color32,
    raised: Color32,
    hover: Color32,
    stroke: Color32,
    text: Color32,
    muted: Color32,
    accent: Color32,
    accent_soft: Color32,
    on_accent: Color32,
    shadow: Color32,
    green: Color32,
    green_soft: Color32,
    amber: Color32,
    amber_soft: Color32,
    red: Color32,
    red_soft: Color32,
    blue: Color32,
}

impl Palette {
    fn for_dark(dark: bool, translucent: bool) -> Self {
        if dark {
            Self {
                canvas: rgba_or_rgb(33, 34, 45, 242, translucent),
                sidebar: rgba_or_rgb(36, 39, 59, 216, translucent),
                toolbar: rgba_or_rgb(39, 41, 65, 194, translucent),
                card: rgba_or_rgb(33, 34, 45, 238, translucent),
                raised: rgba_or_rgb(255, 255, 255, 18, translucent),
                hover: rgba_or_rgb(255, 255, 255, 28, translucent),
                stroke: Color32::from_rgba_unmultiplied(255, 255, 255, 32),
                text: Color32::from_rgb(221, 221, 223),
                muted: Color32::from_rgb(163, 163, 171),
                accent: Color32::from_rgb(10, 132, 255),
                accent_soft: Color32::from_rgba_unmultiplied(10, 132, 255, 31),
                on_accent: Color32::WHITE,
                shadow: Color32::from_rgba_unmultiplied(0, 0, 0, 9),
                green: Color32::from_rgb(48, 209, 88),
                green_soft: Color32::from_rgba_unmultiplied(48, 209, 88, 25),
                amber: Color32::from_rgb(255, 159, 10),
                amber_soft: Color32::from_rgba_unmultiplied(255, 159, 10, 24),
                red: Color32::from_rgb(255, 69, 58),
                red_soft: Color32::from_rgba_unmultiplied(255, 69, 58, 23),
                blue: Color32::from_rgb(100, 210, 255),
            }
        } else {
            Self {
                canvas: rgba_or_rgb(248, 248, 250, 246, translucent),
                sidebar: rgba_or_rgb(246, 246, 249, 218, translucent),
                toolbar: rgba_or_rgb(249, 249, 252, 196, translucent),
                card: rgba_or_rgb(248, 248, 250, 241, translucent),
                raised: rgba_or_rgb(118, 118, 128, 18, translucent),
                hover: rgba_or_rgb(118, 118, 128, 28, translucent),
                stroke: Color32::from_rgba_unmultiplied(60, 60, 67, 32),
                text: Color32::from_rgb(29, 29, 31),
                muted: Color32::from_rgb(110, 110, 115),
                accent: Color32::from_rgb(0, 122, 255),
                accent_soft: Color32::from_rgba_unmultiplied(0, 122, 255, 31),
                on_accent: Color32::WHITE,
                shadow: Color32::from_rgba_unmultiplied(0, 0, 0, 9),
                green: Color32::from_rgb(40, 160, 70),
                green_soft: Color32::from_rgba_unmultiplied(40, 160, 70, 22),
                amber: Color32::from_rgb(196, 112, 0),
                amber_soft: Color32::from_rgba_unmultiplied(196, 112, 0, 20),
                red: Color32::from_rgb(215, 48, 39),
                red_soft: Color32::from_rgba_unmultiplied(215, 48, 39, 20),
                blue: Color32::from_rgb(0, 122, 255),
            }
        }
    }
}

fn rgba_or_rgb(red: u8, green: u8, blue: u8, alpha: u8, translucent: bool) -> Color32 {
    if translucent {
        Color32::from_rgba_unmultiplied(red, green, blue, alpha)
    } else {
        Color32::from_rgb(red, green, blue)
    }
}

fn subtle_card_shadow(palette: Palette) -> Shadow {
    Shadow {
        offset: [0, 3],
        blur: 8,
        spread: 0,
        color: palette.shadow,
    }
}

fn semantic_glyph_button(
    response: egui::Response,
    enabled: bool,
    label: &'static str,
) -> egui::Response {
    response.widget_info(move || WidgetInfo::labeled(WidgetType::Button, enabled, label));
    response
}

#[derive(Debug, Clone, Copy)]
enum ToolbarGlyph {
    Sidebar,
    Previous,
    Next,
    Check,
    Reveal,
    Import,
    Inspector,
}

fn toolbar_glyph_button(
    ui: &mut egui::Ui,
    glyph: ToolbarGlyph,
    enabled: bool,
    label: &'static str,
    palette: Palette,
) -> egui::Response {
    let response = semantic_glyph_button(
        ui.add_enabled(
            enabled,
            Button::new("").frame(false).min_size(Vec2::new(32.0, 32.0)),
        ),
        enabled,
        label,
    );
    let color = if enabled {
        if response.hovered() {
            palette.text
        } else {
            palette.muted
        }
    } else {
        palette.muted.gamma_multiply(0.45)
    };
    paint_toolbar_glyph(ui.painter(), response.rect.shrink(8.0), glyph, color);
    response
}

fn toolbar_material_frame(
    palette: Palette,
    liquid_glass: bool,
    inner_margin: impl Into<Margin>,
) -> Frame {
    let (fill, stroke) = if liquid_glass {
        (Color32::TRANSPARENT, Stroke::new(1.0, Color32::TRANSPARENT))
    } else {
        (palette.raised, Stroke::new(1.0, palette.stroke))
    };
    Frame::new()
        .fill(fill)
        .stroke(stroke)
        .corner_radius(18)
        .inner_margin(inner_margin)
}

fn paint_toolbar_glyph(
    painter: &egui::Painter,
    rect: egui::Rect,
    glyph: ToolbarGlyph,
    color: Color32,
) {
    let center = rect.center();
    let stroke = Stroke::new(1.55, color);
    match glyph {
        ToolbarGlyph::Sidebar | ToolbarGlyph::Inspector => {
            painter.rect_stroke(rect, 2.5, stroke, egui::StrokeKind::Inside);
            let x = if matches!(glyph, ToolbarGlyph::Sidebar) {
                rect.left() + rect.width() * 0.38
            } else {
                rect.right() - rect.width() * 0.38
            };
            painter.line_segment(
                [egui::pos2(x, rect.top()), egui::pos2(x, rect.bottom())],
                stroke,
            );
        }
        ToolbarGlyph::Previous | ToolbarGlyph::Next => {
            let direction = if matches!(glyph, ToolbarGlyph::Previous) {
                -1.0
            } else {
                1.0
            };
            let tip = egui::pos2(center.x + direction * 3.0, center.y);
            let tail_x = center.x - direction * 2.5;
            painter.add(egui::Shape::line(
                vec![
                    egui::pos2(tail_x, center.y - 5.0),
                    tip,
                    egui::pos2(tail_x, center.y + 5.0),
                ],
                Stroke::new(1.9, color),
            ));
        }
        ToolbarGlyph::Check => {
            painter.circle_stroke(center, 6.5, stroke);
            painter.add(egui::Shape::line(
                vec![
                    egui::pos2(center.x - 3.3, center.y),
                    egui::pos2(center.x - 0.7, center.y + 2.7),
                    egui::pos2(center.x + 4.0, center.y - 3.1),
                ],
                stroke,
            ));
        }
        ToolbarGlyph::Reveal => {
            let points = vec![
                egui::pos2(rect.left(), center.y),
                egui::pos2(center.x - 3.2, center.y - 4.0),
                egui::pos2(center.x + 3.2, center.y - 4.0),
                egui::pos2(rect.right(), center.y),
                egui::pos2(center.x + 3.2, center.y + 4.0),
                egui::pos2(center.x - 3.2, center.y + 4.0),
                egui::pos2(rect.left(), center.y),
            ];
            painter.add(egui::Shape::line(points, stroke));
            painter.circle_filled(center, 2.2, color);
        }
        ToolbarGlyph::Import => {
            painter.add(egui::Shape::line(
                vec![
                    egui::pos2(rect.left() + 1.0, center.y + 1.0),
                    egui::pos2(rect.left() + 1.0, rect.bottom() - 1.0),
                    egui::pos2(rect.right() - 1.0, rect.bottom() - 1.0),
                    egui::pos2(rect.right() - 1.0, center.y + 1.0),
                ],
                stroke,
            ));
            painter.line_segment(
                [
                    egui::pos2(center.x, rect.top() + 1.0),
                    egui::pos2(center.x, center.y + 3.0),
                ],
                stroke,
            );
            painter.add(egui::Shape::line(
                vec![
                    egui::pos2(center.x - 3.5, center.y - 0.5),
                    egui::pos2(center.x, center.y + 3.0),
                    egui::pos2(center.x + 3.5, center.y - 0.5),
                ],
                stroke,
            ));
        }
    }
}

#[derive(Debug)]
pub struct AccountingQuestionStudio {
    model: StudioModel,
    active_part: usize,
    revealed_parts: HashSet<String>,
    review_visible: bool,
    library_visible: bool,
    study_settings_expanded: bool,
    filters_expanded: bool,
    search_focus_requested: bool,
    library_scroll_to_selection: bool,
    flash_message: Option<String>,
    #[cfg(target_os = "macos")]
    system_material: Option<crate::macos_material::SystemMaterial>,
    native_material_active: bool,
    native_glass_active: bool,
    traffic_lights_width: f32,
}

impl AccountingQuestionStudio {
    fn new(creation_context: &eframe::CreationContext<'_>) -> Self {
        #[cfg(target_os = "macos")]
        let system_material = crate::macos_material::install_system_material(creation_context).ok();
        #[cfg(target_os = "macos")]
        let native_material_active = system_material.is_some();
        #[cfg(target_os = "macos")]
        let native_glass_active = system_material
            .as_ref()
            .is_some_and(|material| material.liquid_glass_visible());
        #[cfg(not(target_os = "macos"))]
        let native_material_active = false;
        #[cfg(not(target_os = "macos"))]
        let native_glass_active = false;

        #[cfg(target_os = "macos")]
        let traffic_lights_width = creation_context
            .window_handle()
            .ok()
            .and_then(|handle| eframe::WindowChromeMetrics::from_window_handle(&handle.as_raw()))
            .map(|metrics| metrics.traffic_lights_size.x / creation_context.egui_ctx.zoom_factor())
            .unwrap_or(76.0);
        #[cfg(not(target_os = "macos"))]
        let traffic_lights_width = 12.0;

        configure_theme(&creation_context.egui_ctx, native_material_active);
        Self {
            model: StudioModel::load_standard(),
            active_part: 0,
            revealed_parts: HashSet::new(),
            review_visible: true,
            library_visible: true,
            study_settings_expanded: false,
            filters_expanded: false,
            search_focus_requested: false,
            library_scroll_to_selection: true,
            flash_message: None,
            #[cfg(target_os = "macos")]
            system_material,
            native_material_active,
            native_glass_active,
            traffic_lights_width,
        }
    }

    fn palette(&self, ui: &egui::Ui) -> Palette {
        let mut palette = Palette::for_dark(ui.visuals().dark_mode, self.native_material_active);
        if self.native_glass_active {
            palette.toolbar = if ui.visuals().dark_mode {
                Color32::from_rgba_unmultiplied(39, 41, 65, 42)
            } else {
                Color32::from_rgba_unmultiplied(249, 249, 252, 52)
            };
        }
        palette
    }

    fn handle_shortcuts(&mut self, ctx: &egui::Context) {
        let command = Modifiers::COMMAND;
        let command_shift = Modifiers {
            command: true,
            shift: true,
            ..Modifiers::NONE
        };
        if ctx.input_mut(|input| {
            input.consume_shortcut(&KeyboardShortcut::new(command, egui::Key::O))
        }) {
            self.import_with_picker();
        }
        if ctx.input_mut(|input| {
            input.consume_shortcut(&KeyboardShortcut::new(command, egui::Key::S))
        }) {
            self.save_now();
        }
        if ctx.input_mut(|input| {
            input.consume_shortcut(&KeyboardShortcut::new(command, egui::Key::F))
        }) {
            self.search_focus_requested = true;
        }
        if ctx.input_mut(|input| {
            input.consume_shortcut(&KeyboardShortcut::new(command, egui::Key::I))
        }) {
            self.review_visible = !self.review_visible;
        }
        if ctx.input_mut(|input| {
            input.consume_shortcut(&KeyboardShortcut::new(command, egui::Key::Enter))
        }) {
            self.check_active_part();
        }
        if ctx.input_mut(|input| {
            input.consume_shortcut(&KeyboardShortcut::new(command_shift, egui::Key::R))
        }) {
            self.toggle_active_reveal();
        }
        if ctx.input_mut(|input| {
            input.consume_shortcut(&KeyboardShortcut::new(command, egui::Key::OpenBracket))
        }) {
            self.select_question_delta(-1);
        }
        if ctx.input_mut(|input| {
            input.consume_shortcut(&KeyboardShortcut::new(command, egui::Key::CloseBracket))
        }) {
            self.select_question_delta(1);
        }
    }

    fn import_with_picker(&mut self) {
        let Some(paths) = rfd::FileDialog::new()
            .set_title("Import Accounting Question Markdown")
            .add_filter("Markdown", &["md", "markdown"])
            .pick_files()
        else {
            return;
        };
        self.import_paths(paths);
    }

    fn import_paths(&mut self, paths: Vec<PathBuf>) {
        let mut imported_questions = 0;
        let mut warning_count = 0;
        let mut errors = Vec::new();
        for path in paths {
            match self.model.import_path(&path) {
                Ok(summary) => {
                    imported_questions += summary.question_count;
                    warning_count += summary.warnings.len();
                }
                Err(error) => errors.push(error),
            }
        }
        self.active_part = 0;
        if errors.is_empty() {
            let warning_suffix = if warning_count == 0 {
                String::new()
            } else {
                format!(" · {warning_count} import warning(s)")
            };
            self.flash_message = Some(format!(
                "Imported {imported_questions} working question(s){warning_suffix}."
            ));
        } else {
            self.model.last_error = Some(errors.join("\n"));
        }
    }

    fn save_now(&mut self) {
        self.flash_message = match self.model.save_now() {
            Ok(()) => Some("Study progress saved locally.".to_owned()),
            Err(error) => {
                self.model.last_error = Some(error);
                None
            }
        };
    }

    fn part_key(pack_id: &str, question_id: &str, part_id: &str) -> String {
        format!("{pack_id}::{question_id}::{part_id}")
    }

    fn selection_is_visible(&mut self) -> bool {
        let selected_pack = self.model.selected_pack_id.clone();
        let selected_question = self.model.selected_question_id.clone();
        self.model.filtered_questions().iter().any(|item| {
            selected_pack.as_ref() == Some(&item.pack_id)
                && selected_question.as_ref() == Some(&item.question_id)
        })
    }

    fn active_question_and_part(&mut self) -> Option<(AccountingQuestion, QuestionPart)> {
        if !self.selection_is_visible() {
            return None;
        }
        let question = self.model.selected_question()?;
        let part = question.parts.get(self.active_part)?.clone();
        Some((question, part))
    }

    fn check_active_part(&mut self) {
        let Some((question, part)) = self.active_question_and_part() else {
            return;
        };
        let Some(pack_id) = self.model.selected_pack_id.clone() else {
            return;
        };
        if !self
            .model
            .set_part_checked(&pack_id, &question.id, &part.id, true)
        {
            return;
        }
        let key = Self::part_key(&pack_id, &question.id, &part.id);
        if self.model.state.preferences.show_answer_after_check {
            self.revealed_parts.insert(key);
        }
        self.review_visible = true;
    }

    fn toggle_active_reveal(&mut self) {
        let Some((question, part)) = self.active_question_and_part() else {
            return;
        };
        let Some(pack_id) = self.model.selected_pack_id.as_deref() else {
            return;
        };
        let key = Self::part_key(pack_id, &question.id, &part.id);
        if !self.revealed_parts.remove(&key) {
            self.revealed_parts.insert(key);
        }
        self.review_visible = true;
    }

    fn select_question_delta(&mut self, delta: isize) {
        let questions = self.model.filtered_questions();
        if questions.is_empty() {
            return;
        }
        let current = questions.iter().position(|item| {
            self.model.selected_pack_id.as_ref() == Some(&item.pack_id)
                && self.model.selected_question_id.as_ref() == Some(&item.question_id)
        });
        let index = match current {
            Some(index) => (index as isize + delta).clamp(0, questions.len() as isize - 1) as usize,
            None => 0,
        };
        let item = &questions[index];
        self.model.select_question(&item.pack_id, &item.question_id);
        self.active_part = 0;
        self.library_scroll_to_selection = true;
    }

    fn handle_dropped_files(&mut self, ctx: &egui::Context) {
        let paths = ctx.input(|input| {
            input
                .raw
                .dropped_files
                .iter()
                .filter_map(|file| file.path.clone())
                .filter(|path| {
                    path.extension()
                        .and_then(|extension| extension.to_str())
                        .is_some_and(|extension| {
                            extension.eq_ignore_ascii_case("md")
                                || extension.eq_ignore_ascii_case("markdown")
                        })
                })
                .collect::<Vec<_>>()
        });
        if !paths.is_empty() {
            self.import_paths(paths);
        }
    }

    fn show_toolbar(
        &mut self,
        ui: &mut egui::Ui,
    ) -> [Option<egui::Rect>; TOOLBAR_GLASS_REGION_COUNT] {
        let palette = self.palette(ui);
        let active = self.active_question_and_part();
        let selected_pack_id = self.model.selected_pack_id.clone();
        let active_key = selected_pack_id
            .as_deref()
            .zip(active.as_ref())
            .map(|(pack_id, (question, part))| Self::part_key(pack_id, &question.id, &part.id));
        let has_part = active.is_some();
        let revealed = active_key
            .as_ref()
            .is_some_and(|key| self.revealed_parts.contains(key));
        let checked = selected_pack_id
            .as_deref()
            .zip(active.as_ref())
            .is_some_and(|(pack_id, (question, part))| {
                self.model.is_part_checked(pack_id, &question.id, &part.id)
            });
        let can_check = selected_pack_id
            .as_deref()
            .zip(active.as_ref())
            .is_some_and(|(pack_id, (question, part))| {
                self.model.can_check_part(pack_id, &question.id, &part.id)
            });
        let visible_questions = self.model.filtered_questions();
        let selected_index = visible_questions.iter().position(|question| {
            selected_pack_id.as_ref() == Some(&question.pack_id)
                && self.model.selected_question_id.as_ref() == Some(&question.question_id)
        });
        let can_go_previous = selected_index.is_some_and(|index| index > 0);
        let can_go_next = selected_index.is_some_and(|index| index + 1 < visible_questions.len());

        let total_width = ui.available_width();
        let search_width = (total_width * 0.23).clamp(160.0, 320.0);
        const NAVIGATION_GROUP_WIDTH: f32 = 70.0;
        const ACTION_GROUP_WIDTH: f32 = 134.0;
        const GROUP_GAP: f32 = 4.0;

        let mut glass_regions = [None; TOOLBAR_GLASS_REGION_COUNT];
        ui.horizontal_centered(|ui| {
            ui.spacing_mut().item_spacing.x = 0.0;
            ui.add_space(self.traffic_lights_width + 2.0);

            let sidebar_group =
                toolbar_material_frame(palette, self.native_glass_active, 2).show(ui, |ui| {
                    if toolbar_glyph_button(
                        ui,
                        ToolbarGlyph::Sidebar,
                        true,
                        "Toggle Question Library",
                        palette,
                    )
                    .on_hover_text(if self.library_visible {
                        "Hide question library"
                    } else {
                        "Show question library"
                    })
                    .clicked()
                    {
                        self.library_visible = !self.library_visible;
                    }
                });
            glass_regions[0] = Some(sidebar_group.response.rect);

            let right_cluster_width = NAVIGATION_GROUP_WIDTH
                + GROUP_GAP
                + ACTION_GROUP_WIDTH
                + GROUP_GAP
                + search_width
                + 2.0;
            ui.add_space((ui.available_width() - right_cluster_width).max(8.0));

            let navigation_group = toolbar_material_frame(palette, self.native_glass_active, 2)
                .show(ui, |ui| {
                    ui.spacing_mut().item_spacing.x = 0.0;
                    if toolbar_glyph_button(
                        ui,
                        ToolbarGlyph::Previous,
                        can_go_previous,
                        "Previous Question",
                        palette,
                    )
                    .on_hover_text("Previous question (⌘[)")
                    .clicked()
                    {
                        self.select_question_delta(-1);
                    }
                    if toolbar_glyph_button(
                        ui,
                        ToolbarGlyph::Next,
                        can_go_next,
                        "Next Question",
                        palette,
                    )
                    .on_hover_text("Next question (⌘])")
                    .clicked()
                    {
                        self.select_question_delta(1);
                    }
                });
            glass_regions[1] = Some(navigation_group.response.rect);

            ui.add_space(GROUP_GAP);
            let action_group =
                toolbar_material_frame(palette, self.native_glass_active, 2).show(ui, |ui| {
                    ui.spacing_mut().item_spacing.x = 0.0;
                    if toolbar_glyph_button(
                        ui,
                        ToolbarGlyph::Check,
                        has_part && can_check && !checked,
                        "Check Response",
                        palette,
                    )
                    .on_hover_text(if checked {
                        "Response checked; edit it to check again"
                    } else if !can_check {
                        "Enter a response before checking"
                    } else {
                        "Check the current response (⌘Return)"
                    })
                    .clicked()
                    {
                        self.check_active_part();
                    }
                    if toolbar_glyph_button(
                        ui,
                        ToolbarGlyph::Reveal,
                        has_part,
                        "Toggle Model Answer",
                        palette,
                    )
                    .on_hover_text(if revealed {
                        "Hide the current model answer (⌘⇧R)"
                    } else {
                        "Reveal the current model answer (⌘⇧R)"
                    })
                    .clicked()
                    {
                        self.toggle_active_reveal();
                    }
                    if toolbar_glyph_button(
                        ui,
                        ToolbarGlyph::Import,
                        true,
                        "Import Markdown",
                        palette,
                    )
                    .on_hover_text("Import Markdown question packs (⌘O)")
                    .clicked()
                    {
                        self.import_with_picker();
                    }
                    if toolbar_glyph_button(
                        ui,
                        ToolbarGlyph::Inspector,
                        true,
                        "Toggle Inspector",
                        palette,
                    )
                    .on_hover_text(if self.review_visible {
                        "Hide inspector (⌘I)"
                    } else {
                        "Show inspector (⌘I)"
                    })
                    .clicked()
                    {
                        self.review_visible = !self.review_visible;
                    }
                });
            glass_regions[2] = Some(action_group.response.rect);

            ui.add_space(GROUP_GAP);
            let search_group =
                toolbar_material_frame(palette, self.native_glass_active, Margin::symmetric(10, 2))
                    .show(ui, |ui| {
                        ui.add_sized(
                            [search_width - 20.0, 30.0],
                            TextEdit::singleline(&mut self.model.search)
                                .id_salt("library_search")
                                .hint_text("Search questions")
                                .vertical_align(Align::Center)
                                .frame(Frame::new().inner_margin(Margin::symmetric(0, 8))),
                        )
                    });
            glass_regions[3] = Some(search_group.response.rect);
            let search_response = search_group
                .inner
                .on_hover_text("Search titles, tags, scenarios, and formats (⌘F)");
            if self.search_focus_requested {
                search_response.request_focus();
                self.search_focus_requested = false;
            }
        });
        glass_regions
    }

    fn show_library(&mut self, ui: &mut egui::Ui) {
        let palette = self.palette(ui);
        let selected_filter_count = usize::from(self.model.library_pack_filter.is_some())
            + usize::from(self.model.format_filter.is_some())
            + usize::from(self.model.shell_filter.is_some());
        let filters_active = selected_filter_count > 0 || !self.model.search.trim().is_empty();
        ui.add_space(5.0);
        ui.horizontal(|ui| {
            let filter_response = ui.add(
                Button::new("Formats")
                    .small()
                    .frame(false)
                    .min_size(Vec2::new(92.0, 28.0)),
            );
            paint_filter_control(
                ui.painter(),
                filter_response.rect,
                self.filters_expanded,
                palette.muted,
            );
            if filter_response
                .on_hover_text(if self.filters_expanded {
                    "Hide library filters"
                } else {
                    "Show pack, format, and shell filters"
                })
                .clicked()
            {
                self.filters_expanded = !self.filters_expanded;
            }
            if selected_filter_count > 0 {
                chip(
                    ui,
                    selected_filter_count.to_string(),
                    palette.accent_soft,
                    palette.accent,
                );
            }
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                ui.label(
                    RichText::new(self.model.filtered_questions().len().to_string())
                        .size(10.0)
                        .monospace()
                        .color(palette.muted),
                );
                if filters_active
                    && ui
                        .add(Button::new("Clear").small().frame(false))
                        .on_hover_text("Clear search and library filters")
                        .clicked()
                {
                    self.model.search.clear();
                    self.model.format_filter = None;
                    self.model.shell_filter = None;
                    self.model.library_pack_filter = None;
                }
            });
        });

        if self.filters_expanded {
            ui.add_space(3.0);
            Frame::new()
                .fill(palette.raised)
                .corner_radius(8)
                .inner_margin(8)
                .show(ui, |ui| {
                    ui.set_width(ui.available_width());
                    let packs = self.model.pack_choices();
                    let pack_label = self
                        .model
                        .library_pack_filter
                        .as_ref()
                        .and_then(|id| packs.iter().find(|pack| &pack.0 == id))
                        .map_or_else(|| "All question packs".to_owned(), |pack| pack.1.clone());
                    ComboBox::from_id_salt("pack_filter")
                        .selected_text(pack_label)
                        .width(ui.available_width())
                        .show_ui(ui, |ui| {
                            ui.selectable_value(
                                &mut self.model.library_pack_filter,
                                None,
                                format!("All question packs ({})", packs.len()),
                            );
                            for (id, title, count) in &packs {
                                ui.selectable_value(
                                    &mut self.model.library_pack_filter,
                                    Some(id.clone()),
                                    format!("{title} · {count}"),
                                );
                            }
                        });

                    ui.columns(2, |columns| {
                        let format_text = self.model.format_filter.map_or_else(
                            || "All formats".to_owned(),
                            |value| format_label(value).to_owned(),
                        );
                        ComboBox::from_id_salt("format_filter")
                            .selected_text(format_text)
                            .width(columns[0].available_width())
                            .show_ui(&mut columns[0], |ui| {
                                ui.selectable_value(
                                    &mut self.model.format_filter,
                                    None,
                                    "All formats",
                                );
                                ui.separator();
                                ScrollArea::vertical().max_height(360.0).show(ui, |ui| {
                                    for format in QuestionFormat::ALL {
                                        ui.selectable_value(
                                            &mut self.model.format_filter,
                                            Some(*format),
                                            format_label(*format),
                                        );
                                    }
                                });
                            });

                        let shell_text = self.model.shell_filter.map_or_else(
                            || "All shells".to_owned(),
                            |value| shell_label(value).to_owned(),
                        );
                        ComboBox::from_id_salt("shell_filter")
                            .selected_text(shell_text)
                            .width(columns[1].available_width())
                            .show_ui(&mut columns[1], |ui| {
                                ui.selectable_value(
                                    &mut self.model.shell_filter,
                                    None,
                                    "All shells",
                                );
                                for shell in QuestionShell::ALL {
                                    ui.selectable_value(
                                        &mut self.model.shell_filter,
                                        Some(*shell),
                                        shell_label(*shell),
                                    );
                                }
                            });
                    });
                });
        }

        ui.add_space(4.0);
        ui.separator();
        let questions = self.model.filtered_questions();
        let selection_visible = questions.iter().any(|item| {
            self.model.selected_pack_id.as_ref() == Some(&item.pack_id)
                && self.model.selected_question_id.as_ref() == Some(&item.question_id)
        });
        if !selection_visible && let Some(first) = questions.first() {
            self.model
                .select_question(&first.pack_id, &first.question_id);
            self.active_part = 0;
        }
        if questions.is_empty() {
            empty_library_card(ui, palette);
        } else {
            let selected_pack = self.model.selected_pack_id.clone();
            let selected_question = self.model.selected_question_id.clone();
            let mut selection: Option<(String, String)> = None;
            let selected_index = questions.iter().position(|item| {
                selected_pack.as_ref() == Some(&item.pack_id)
                    && selected_question.as_ref() == Some(&item.question_id)
            });
            let mut scroll_area = ScrollArea::vertical()
                .id_salt("question_library_scroll")
                .auto_shrink([false, false]);
            if self.library_scroll_to_selection {
                if let Some(selected_index) = selected_index {
                    scroll_area = scroll_area
                        .vertical_scroll_offset(selected_index.saturating_sub(2) as f32 * 82.0);
                }
                self.library_scroll_to_selection = false;
            }
            scroll_area.show_rows(ui, 82.0, questions.len(), |ui, visible_rows| {
                ui.set_width(ui.available_width());
                for index in visible_rows {
                    let item = &questions[index];
                    let selected = selected_pack.as_ref() == Some(&item.pack_id)
                        && selected_question.as_ref() == Some(&item.question_id);
                    ui.allocate_ui_with_layout(
                        Vec2::new(ui.available_width(), 82.0),
                        Layout::top_down(Align::Min),
                        |ui| {
                            if library_question_row(ui, item, selected, palette) {
                                selection = Some((item.pack_id.clone(), item.question_id.clone()));
                            }
                        },
                    );
                }
            });
            if let Some((pack_id, question_id)) = selection {
                self.model.select_question(&pack_id, &question_id);
                self.active_part = 0;
            }
        }
    }

    fn show_question_canvas(&mut self, ui: &mut egui::Ui) {
        if !self.selection_is_visible() {
            let palette = self.palette(ui);
            ui.centered_and_justified(|ui| {
                Frame::new()
                    .fill(palette.card)
                    .stroke(Stroke::new(1.0, palette.stroke))
                    .corner_radius(14)
                    .inner_margin(24)
                    .show(ui, |ui| {
                        ui.vertical_centered(|ui| {
                            ui.label(RichText::new("No Matching Questions").size(16.0).strong());
                            ui.label(
                                RichText::new(
                                    "Adjust the search or filters to return to your saved work.",
                                )
                                .size(12.0)
                                .color(palette.muted),
                            );
                            ui.add_space(8.0);
                            if ui.button("Clear Search and Filters").clicked() {
                                self.model.search.clear();
                                self.model.format_filter = None;
                                self.model.shell_filter = None;
                                self.model.library_pack_filter = None;
                            }
                        });
                    });
            });
            return;
        }
        let Some(pack_id) = self.model.selected_pack_id.clone() else {
            return;
        };
        let Some(question) = self.model.selected_question() else {
            let palette = self.palette(ui);
            ui.centered_and_justified(|ui| {
                Frame::new()
                    .fill(palette.card)
                    .stroke(Stroke::new(1.0, palette.stroke))
                    .corner_radius(14)
                    .inner_margin(28)
                    .show(ui, |ui| {
                        ui.heading("No question selected");
                        ui.label("Choose a question in the library or import a Markdown pack.");
                    });
            });
            return;
        };
        self.active_part = self.active_part.min(question.parts.len().saturating_sub(1));

        let palette = self.palette(ui);
        egui::CentralPanel::no_frame().show(ui, |ui| {
            ScrollArea::vertical()
                .id_salt("question_canvas_scroll")
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    let available_width = ui.available_width();
                    let edge_padding = if available_width >= 640.0 { 34.0 } else { 20.0 };
                    let content_width =
                        (available_width - edge_padding * 2.0).clamp(240.0, 900.0);
                    let gutter = ((available_width - content_width) / 2.0).max(0.0);

                    ui.horizontal_top(|ui| {
                        ui.add_space(gutter);
                        ui.vertical(|ui| {
                            ui.set_width(content_width);
                            ui.add_space(30.0);
                            self.show_status_messages(ui);

                            ui.add(
                                Label::new(
                                    RichText::new(&question.title)
                                        .size(26.0)
                                        .strong()
                                        .color(palette.text),
                                )
                                .wrap(),
                            );
                            ui.add_space(13.0);
                            ui.horizontal_wrapped(|ui| {
                                ui.label(
                                    RichText::new(format!("▧  {}", shell_label(question.shell)))
                                        .size(13.0)
                                        .color(palette.muted),
                                );
                                if !question.source_name.trim().is_empty() {
                                    ui.label(RichText::new("|").color(palette.stroke));
                                    ui.label(
                                        RichText::new(format!("▤  {}", question.source_name))
                                            .size(13.0)
                                            .color(palette.muted),
                                    );
                                }
                            });

                            let (answered, _mastered) =
                                self.model.question_progress(&pack_id, &question);
                            let total = question.parts.len();
                            let checked_count = question
                                .parts
                                .iter()
                                .filter(|part| {
                                    self.model.is_part_checked(
                                        &pack_id,
                                        &question.id,
                                        &part.id,
                                    )
                                })
                                .count();
                            let fraction = if total == 0 {
                                0.0
                            } else {
                                answered as f32 / total as f32
                            };
                            ui.add_space(13.0);
                            ui.horizontal(|ui| {
                                ui.label(
                                    RichText::new(format!(
                                        "{answered} of {total} parts answered"
                                    ))
                                    .size(11.0)
                                    .color(palette.muted),
                                );
                                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                                    ui.label(
                                        RichText::new(format!("{checked_count} checked"))
                                            .size(11.0)
                                            .color(palette.muted),
                                    );
                                });
                            });
                            ui.add(
                                ProgressBar::new(fraction)
                                    .desired_width(ui.available_width())
                                    .desired_height(6.0)
                                    .fill(palette.accent),
                            )
                            .on_hover_text("Progress is saved locally; mastery requires a correct answer or completed self-review.");

                            if !question.scenario_markdown.trim().is_empty() {
                                ui.add_space(26.0);
                                Frame::new()
                                    .fill(palette.raised)
                                    .corner_radius(12)
                                    .inner_margin(18)
                                    .show(ui, |ui| {
                                        ui.label(
                                            RichText::new("▤  Scenario").size(13.0).strong(),
                                        );
                                        ui.add_space(10.0);
                                        render_markdown(
                                            ui,
                                            &question.scenario_markdown,
                                            palette,
                                            13.0,
                                        );
                                    });
                            }

                            ui.add_space(26.0);
                            ui.label(
                                RichText::new("Required Responses")
                                    .size(17.0)
                                    .strong()
                                    .color(palette.text),
                            );
                            ui.add_space(16.0);

                            if question.parts.is_empty() {
                                warning_card(ui, "This question has no answer parts.", palette);
                            } else {
                                let question_grade = self.model.grade_for(&pack_id, &question);
                                for (index, part) in question.parts.iter().cloned().enumerate() {
                                    self.show_part_editor(
                                        ui,
                                        &pack_id,
                                        &question,
                                        &part,
                                        index,
                                        question_grade.parts.get(index).cloned(),
                                    );
                                    ui.add_space(16.0);
                                }
                            }
                            ui.add_space(14.0);
                        });
                    });
                });
        });
    }

    fn show_status_messages(&mut self, ui: &mut egui::Ui) {
        let palette = self.palette(ui);
        if let Some(error) = &self.model.last_error {
            Frame::new()
                .fill(palette.red_soft)
                .stroke(Stroke::new(1.0, palette.red))
                .corner_radius(9)
                .inner_margin(12)
                .show(ui, |ui| {
                    ui.label(
                        RichText::new("Import or save problem")
                            .strong()
                            .color(palette.red),
                    );
                    ui.label(RichText::new(error).color(palette.text));
                });
            ui.add_space(8.0);
        }
        if let Some(message) = &self.flash_message {
            Frame::new()
                .fill(palette.accent_soft)
                .stroke(Stroke::new(1.0, palette.accent))
                .corner_radius(9)
                .inner_margin(12)
                .show(ui, |ui| {
                    ui.horizontal_wrapped(|ui| {
                        ui.label(RichText::new("Ready").strong().color(palette.accent));
                        ui.label(message);
                    });
                });
            ui.add_space(8.0);
        }
        if let Some(summary) = &self.model.last_import
            && !summary.warnings.is_empty()
        {
            Frame::new()
                .fill(palette.amber_soft)
                .stroke(Stroke::new(1.0, palette.amber))
                .corner_radius(9)
                .inner_margin(12)
                .show(ui, |ui| {
                    ui.label(
                        RichText::new(format!(
                            "{} imported with {} warning(s)",
                            summary.source_name,
                            summary.warnings.len()
                        ))
                        .strong()
                        .color(palette.amber),
                    );
                    for warning in &summary.warnings {
                        let line = warning
                            .line
                            .map_or_else(String::new, |line| format!("Line {line}: "));
                        ui.label(format!("• {line}{}", warning.message));
                    }
                });
            ui.add_space(8.0);
        }
    }

    fn show_part_editor(
        &mut self,
        ui: &mut egui::Ui,
        pack_id: &str,
        question: &AccountingQuestion,
        part: &QuestionPart,
        part_index: usize,
        part_grade: Option<PartGrade>,
    ) {
        let palette = self.palette(ui);
        let key = Self::part_key(pack_id, &question.id, &part.id);
        let checked = self.model.is_part_checked(pack_id, &question.id, &part.id);
        let revealed = self.revealed_parts.contains(&key);
        let is_active = self.active_part == part_index;

        let card = Frame::new()
            .fill(palette.card)
            .stroke(Stroke::new(
                if is_active { 1.5 } else { 1.0 },
                if is_active {
                    palette.accent.gamma_multiply(0.55)
                } else {
                    palette.stroke
                },
            ))
            .corner_radius(14)
            .inner_margin(20)
            .shadow(subtle_card_shadow(palette))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 12.0;
                    let (badge_rect, _) = ui.allocate_exact_size(Vec2::splat(30.0), Sense::hover());
                    ui.painter()
                        .circle_filled(badge_rect.center(), 15.0, palette.accent_soft);
                    ui.painter().text(
                        badge_rect.center(),
                        egui::Align2::CENTER_CENTER,
                        (part_index + 1).to_string(),
                        FontId::new(13.0, FontFamily::Monospace),
                        palette.accent,
                    );
                    ui.vertical(|ui| {
                        ui.spacing_mut().item_spacing.y = 4.0;
                        ui.label(
                            RichText::new(format_label(part.format))
                                .size(13.0)
                                .strong()
                                .color(palette.text),
                        );
                        ui.label(
                            RichText::new(format!(
                                "{}  •  {} points",
                                response_kind_label(part.kind),
                                trim_points(part.points)
                            ))
                            .size(10.0)
                            .color(palette.muted),
                        );
                    });
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if checked && let Some(part_grade) = &part_grade {
                            let (color, label) =
                                grade_status_style(part_grade.result.status, palette);
                            ui.label(RichText::new(format!("● {label}")).size(11.0).color(color));
                        }
                    });
                });
                ui.add_space(16.0);
                render_markdown(ui, &part.prompt_markdown, palette, 13.0);
                ui.add_space(16.0);
                ui.separator();
                ui.add_space(16.0);

                let changed = {
                    let answer = self.model.answer_mut(pack_id, &question.id, &part.id);
                    draw_response_editor(ui, part, answer, palette, &key)
                };
                if changed {
                    self.active_part = part_index;
                    self.model
                        .set_part_checked(pack_id, &question.id, &part.id, false);
                    self.model.touch_attempt(pack_id, &question.id);
                    self.flash_message = None;
                }
                let checked_after_edit =
                    self.model.is_part_checked(pack_id, &question.id, &part.id);
                let can_check = self.model.can_check_part(pack_id, &question.id, &part.id);

                if checked_after_edit && let Some(part_grade) = &part_grade {
                    ui.add_space(16.0);
                    grade_banner(ui, &part_grade.result, palette);
                }

                ui.add_space(16.0);
                ui.horizontal_wrapped(|ui| {
                    let check_button = if checked_after_edit {
                        Button::new(RichText::new("✓  Checked").strong())
                            .fill(palette.raised)
                            .stroke(Stroke::new(1.0, palette.stroke))
                    } else {
                        Button::new(
                            RichText::new("✓  Check Answer")
                                .strong()
                                .color(palette.on_accent),
                        )
                        .fill(palette.accent)
                        .stroke(Stroke::NONE)
                    };
                    if ui
                        .add_enabled(can_check && !checked_after_edit, check_button)
                        .on_hover_text(if checked_after_edit {
                            "Response checked; edit it to check again"
                        } else if !can_check {
                            "Enter a response before checking"
                        } else {
                            "Check this response (⌘Return when current)"
                        })
                        .clicked()
                    {
                        self.active_part = part_index;
                        self.check_active_part();
                    }
                    if ui
                        .button(if revealed {
                            "◉  Hide Answer"
                        } else {
                            "◎  Reveal Answer"
                        })
                        .on_hover_text("Show or hide the model answer")
                        .clicked()
                    {
                        self.active_part = part_index;
                        self.toggle_active_reveal();
                    }
                });

                if revealed {
                    ui.add_space(16.0);
                    Frame::new()
                        .fill(palette.raised)
                        .stroke(Stroke::new(1.0, palette.stroke))
                        .corner_radius(10)
                        .inner_margin(14)
                        .show(ui, |ui| {
                            ui.label(RichText::new("Model Answer").size(13.0).strong());
                            ui.add_space(6.0);
                            show_expected_answer(ui, part, palette);
                            if !part.rubric_markdown.trim().is_empty() {
                                ui.add_space(10.0);
                                ui.separator();
                                ui.add_space(8.0);
                                ui.label(RichText::new("Rubric").size(13.0).strong());
                                ui.add_space(6.0);
                                render_markdown(ui, &part.rubric_markdown, palette, 13.0);
                            }
                        });
                }

                let self_review_recorded = self
                    .model
                    .attempt_for(pack_id, &question.id)
                    .and_then(|attempt| attempt.self_reviews.get(&part.id))
                    .copied()
                    .unwrap_or(false);
                let needs_self_review = part_grade
                    .as_ref()
                    .is_some_and(|grade| grade.result.status == GradeStatus::NeedsSelfReview)
                    || self_review_recorded;
                if revealed && needs_self_review {
                    ui.add_space(12.0);
                    let mut reviewed = self_review_recorded;
                    if ui
                        .checkbox(
                            &mut reviewed,
                            "I compared my response with the model answer and rubric",
                        )
                        .changed()
                    {
                        self.model
                            .set_self_review(pack_id, &question.id, &part.id, reviewed);
                    }
                }
            });

        if card.response.contains_pointer() && ui.input(|input| input.pointer.any_pressed()) {
            self.active_part = part_index;
        }
    }

    fn show_review(&mut self, ui: &mut egui::Ui) {
        let palette = self.palette(ui);
        if !self.selection_is_visible() {
            ui.label("No matching question to inspect.");
            return;
        }

        let Some(pack_id) = self.model.selected_pack_id.clone() else {
            ui.label("Select a question pack to inspect.");
            return;
        };
        let Some(question) = self.model.selected_question() else {
            ui.label("Select a question to inspect.");
            return;
        };
        let Some(part) = question.parts.get(self.active_part).cloned() else {
            ui.label("This question has no inspectable parts.");
            return;
        };

        let active_key = Self::part_key(&pack_id, &question.id, &part.id);
        let checked = self.model.is_part_checked(&pack_id, &question.id, &part.id);
        let can_check = self.model.can_check_part(&pack_id, &question.id, &part.id);
        let revealed = self.revealed_parts.contains(&active_key);
        let grade = self.model.grade_for(&pack_id, &question);
        let active_grade = grade.parts.get(self.active_part).cloned();
        let total = question.parts.len();
        let (answered, _) = self.model.question_progress(&pack_id, &question);
        let checked_count = question
            .parts
            .iter()
            .filter(|part| self.model.is_part_checked(&pack_id, &question.id, &part.id))
            .count();
        let visible_points = grade
            .parts
            .iter()
            .zip(&question.parts)
            .filter(|(_, part)| self.model.is_part_checked(&pack_id, &question.id, &part.id))
            .map(|(grade, _)| grade.awarded_points)
            .sum::<f64>();
        let progress_fraction = if total == 0 {
            0.0
        } else {
            answered as f32 / total as f32
        };

        ScrollArea::vertical()
            .id_salt("review_scroll")
            .auto_shrink([false, false])
            .show(ui, |ui| {
                ui.set_width(ui.available_width());
                ui.add_space(10.0);

                inspector_section_title(ui, "Progress", palette);
                Frame::new()
                    .fill(palette.card)
                    .stroke(Stroke::new(1.0, palette.stroke))
                    .corner_radius(9)
                    .inner_margin(10)
                    .show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        ui.add(
                            ProgressBar::new(progress_fraction)
                                .desired_width(ui.available_width())
                                .desired_height(4.0)
                                .fill(palette.accent),
                        );
                        ui.add_space(4.0);
                        inspector_value_row(
                            ui,
                            "Answered",
                            &format!("{answered} of {total}"),
                            palette,
                            true,
                        );
                        inspector_value_row(
                            ui,
                            "Checked",
                            &format!("{checked_count} of {total}"),
                            palette,
                            true,
                        );
                        inspector_value_row(
                            ui,
                            "Points",
                            &format!(
                                "{} / {}",
                                trim_points(visible_points),
                                trim_points(grade.possible_points)
                            ),
                            palette,
                            true,
                        );
                    });

                ui.add_space(10.0);
                inspector_section_title(ui, "Current Response", palette);
                Frame::new()
                    .fill(palette.card)
                    .stroke(Stroke::new(1.0, palette.stroke))
                    .corner_radius(9)
                    .inner_margin(10)
                    .show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        inspector_value_row(ui, "Part", &part.id, palette, true);
                        inspector_value_row(
                            ui,
                            "Format",
                            format_label(part.format),
                            palette,
                            false,
                        );
                        inspector_value_row(
                            ui,
                            "Editor",
                            response_kind_label(part.kind),
                            palette,
                            false,
                        );
                        ui.add_space(4.0);
                        if checked {
                            if let Some(active_grade) = &active_grade {
                                grade_banner(ui, &active_grade.result, palette);
                            }
                        } else {
                            ui.label(
                                RichText::new("○  Not checked yet")
                                    .size(11.0)
                                    .color(palette.muted),
                            );
                        }
                        ui.add_space(6.0);
                        ui.horizontal_wrapped(|ui| {
                            if ui
                                .add_enabled(
                                    can_check && !checked,
                                    Button::new(if checked { "Checked" } else { "Check" }),
                                )
                                .on_hover_text(if checked {
                                    "Edit the response to check again"
                                } else if !can_check {
                                    "Enter a response before checking"
                                } else {
                                    "Check the current response"
                                })
                                .clicked()
                            {
                                self.check_active_part();
                            }
                            if ui
                                .button(if revealed {
                                    "Hide Answer"
                                } else {
                                    "Reveal Answer"
                                })
                                .on_hover_text("Show or hide the model answer in the response card")
                                .clicked()
                            {
                                self.toggle_active_reveal();
                            }
                        });

                        let self_review_recorded = self
                            .model
                            .attempt_for(&pack_id, &question.id)
                            .and_then(|attempt| attempt.self_reviews.get(&part.id))
                            .copied()
                            .unwrap_or(false);
                        let needs_self_review = active_grade.as_ref().is_some_and(|grade| {
                            grade.result.status == GradeStatus::NeedsSelfReview
                        }) || self_review_recorded;
                        if needs_self_review {
                            ui.add_space(6.0);
                            let mut reviewed = self_review_recorded;
                            let response = ui.add_enabled_ui(revealed, |ui| {
                                ui.checkbox(&mut reviewed, "Self-review complete")
                            });
                            if response.inner.changed() {
                                self.model.set_self_review(
                                    &pack_id,
                                    &question.id,
                                    &part.id,
                                    reviewed,
                                );
                            }
                        }
                    });

                ui.add_space(10.0);
                inspector_section_title(ui, "Identity", palette);
                Frame::new()
                    .fill(palette.card)
                    .stroke(Stroke::new(1.0, palette.stroke))
                    .corner_radius(9)
                    .inner_margin(10)
                    .show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        inspector_value_row(ui, "Question ID", &question.id, palette, true);
                        inspector_value_row(ui, "Source", &question.source_name, palette, false);
                    });

                ui.add_space(10.0);
                inspector_section_title(ui, "Structure", palette);
                Frame::new()
                    .fill(palette.card)
                    .stroke(Stroke::new(1.0, palette.stroke))
                    .corner_radius(9)
                    .inner_margin(10)
                    .show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        inspector_value_row(
                            ui,
                            "Shell",
                            shell_label(question.shell),
                            palette,
                            false,
                        );
                        inspector_value_row(
                            ui,
                            "Variation",
                            &humanize(question.variation.as_str()),
                            palette,
                            false,
                        );
                        inspector_value_row(ui, "Parts", &total.to_string(), palette, true);
                    });

                ui.add_space(10.0);
                inspector_section_title(ui, "Taxonomy", palette);
                Frame::new()
                    .fill(palette.card)
                    .stroke(Stroke::new(1.0, palette.stroke))
                    .corner_radius(9)
                    .inner_margin(10)
                    .show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        if question.formats.is_empty() {
                            inspector_value_row(ui, "Formats", "None", palette, false);
                        } else {
                            for format in &question.formats {
                                ui.label(
                                    RichText::new(format!("⌑  {}", format_label(*format)))
                                        .size(11.0),
                                );
                            }
                        }
                        let tags = if question.tags.is_empty() {
                            "None".to_owned()
                        } else {
                            question.tags.join(", ")
                        };
                        inspector_value_row(ui, "Tags", &tags, palette, false);
                    });

                ui.add_space(10.0);
                let disclosure = if self.study_settings_expanded {
                    "Study Settings  −"
                } else {
                    "Study Settings  +"
                };
                if ui
                    .add(Button::new(disclosure).small().frame(false))
                    .on_hover_text("Show local saving and answer-reveal preferences")
                    .clicked()
                {
                    self.study_settings_expanded = !self.study_settings_expanded;
                }
                if self.study_settings_expanded {
                    Frame::new()
                        .fill(palette.card)
                        .stroke(Stroke::new(1.0, palette.stroke))
                        .corner_radius(9)
                        .inner_margin(10)
                        .show(ui, |ui| {
                            let mut autosave = self.model.state.preferences.autosave_answers;
                            if ui.checkbox(&mut autosave, "Autosave answers").changed() {
                                self.model.set_autosave(autosave);
                            }
                            let mut reveal_after_check =
                                self.model.state.preferences.show_answer_after_check;
                            if ui
                                .checkbox(&mut reveal_after_check, "Reveal after checking")
                                .changed()
                            {
                                self.model.set_reveal_after_check(reveal_after_check);
                            }
                            if ui.button("Save Now").clicked() {
                                self.save_now();
                            }
                        });
                }

                ui.add_space(12.0);
            });
    }

    fn show_workspace(
        &mut self,
        root: &mut egui::Ui,
    ) -> [Option<egui::Rect>; TOOLBAR_GLASS_REGION_COUNT] {
        let palette = self.palette(root);
        let compact_width = root.available_width() < 980.0;
        let glass_regions = Panel::top("studio_toolbar")
            .exact_size(52.0)
            .frame(
                Frame::new()
                    .fill(palette.toolbar)
                    .stroke(Stroke::new(1.0, palette.stroke))
                    .inner_margin(Margin::symmetric(8, 8)),
            )
            .show(root, |ui| self.show_toolbar(ui))
            .inner;

        if self.library_visible {
            Panel::left("library_panel")
                .default_size(if compact_width { 210.0 } else { 270.0 })
                .size_range(if compact_width {
                    185.0..=230.0
                } else {
                    220.0..=380.0
                })
                .frame(
                    Frame::new()
                        .fill(palette.sidebar)
                        .stroke(Stroke::new(1.0, palette.stroke))
                        .inner_margin(Margin::symmetric(10, 0)),
                )
                .show(root, |ui| self.show_library(ui));
        }

        let show_review = self.review_visible && !compact_width && self.selection_is_visible();
        if show_review {
            Panel::right("review_panel")
                .default_size(280.0)
                .size_range(240.0..=400.0)
                .frame(
                    Frame::new()
                        .fill(palette.sidebar)
                        .stroke(Stroke::new(1.0, palette.stroke))
                        .inner_margin(Margin::symmetric(12, 0)),
                )
                .show(root, |ui| self.show_review(ui));
        }

        egui::CentralPanel::default_margins()
            .frame(Frame::new().fill(palette.canvas).inner_margin(0))
            .show(root, |ui| self.show_question_canvas(ui));
        glass_regions
    }
}

impl eframe::App for AccountingQuestionStudio {
    fn logic(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.model.save_if_due();
        if self.model.is_dirty() && self.model.state.preferences.autosave_answers {
            ctx.request_repaint_after(Duration::from_millis(700));
        }
    }

    fn ui(&mut self, root: &mut egui::Ui, _frame: &mut eframe::Frame) {
        self.handle_shortcuts(root.ctx());
        self.handle_dropped_files(root.ctx());
        let viewport = root.ctx().viewport_rect();
        let viewport_origin = viewport.min;
        let glass_regions = self.show_workspace(root);
        #[cfg(target_os = "macos")]
        if let Some(material) = &self.system_material {
            let native_regions = glass_regions.map(|region| {
                region.map(|rect| {
                    crate::macos_material::GlassRect::new(
                        rect.min.x - viewport_origin.x,
                        rect.min.y - viewport_origin.y,
                        rect.max.x - viewport_origin.x,
                        rect.max.y - viewport_origin.y,
                    )
                })
            });
            let glass_active =
                material.update_toolbar_glass(native_regions, viewport.width(), viewport.height());
            if glass_active != self.native_glass_active {
                self.native_glass_active = glass_active;
                root.ctx().request_repaint();
            }
        }
        #[cfg(not(target_os = "macos"))]
        let _ = (viewport_origin, glass_regions);
    }

    fn on_exit(&mut self, _gl: Option<&eframe::glow::Context>) {
        let _ = self.model.save_now();
    }

    fn clear_color(&self, visuals: &egui::Visuals) -> [f32; 4] {
        if self.native_material_active {
            [0.0, 0.0, 0.0, 0.0]
        } else {
            Palette::for_dark(visuals.dark_mode, false)
                .canvas
                .to_normalized_gamma_f32()
        }
    }
}

pub fn run() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_app_id(APP_IDENTIFIER)
            .with_title(APP_TITLE)
            .with_inner_size([1_180.0, 760.0])
            .with_min_inner_size([760.0, 540.0])
            .with_transparent(cfg!(target_os = "macos"))
            .with_fullsize_content_view(cfg!(target_os = "macos"))
            .with_title_shown(!cfg!(target_os = "macos"))
            .with_titlebar_shown(!cfg!(target_os = "macos")),
        centered: true,
        ..Default::default()
    };

    eframe::run_native(
        APP_TITLE,
        options,
        Box::new(|creation_context| Ok(Box::new(AccountingQuestionStudio::new(creation_context)))),
    )
}

fn configure_theme(ctx: &egui::Context, translucent: bool) {
    ctx.enable_accesskit();
    ctx.set_theme(ThemePreference::System);
    configure_fonts(ctx);
    for theme in [Theme::Light, Theme::Dark] {
        let dark = theme == Theme::Dark;
        let palette = Palette::for_dark(dark, translucent);
        let mut style = egui::Style {
            visuals: if dark {
                egui::Visuals::dark()
            } else {
                egui::Visuals::light()
            },
            ..Default::default()
        };
        style.spacing.item_spacing = Vec2::new(7.0, 6.0);
        style.spacing.button_padding = Vec2::new(8.0, 4.0);
        style.spacing.interact_size = Vec2::new(32.0, 28.0);
        style.spacing.window_margin = Margin::same(12);
        style.visuals.panel_fill = palette.canvas;
        style.visuals.window_fill = palette.card;
        style.visuals.extreme_bg_color = palette.raised;
        style.visuals.text_edit_bg_color = Some(palette.card);
        style.visuals.faint_bg_color = palette.raised;
        style.visuals.code_bg_color = palette.raised;
        style.visuals.override_text_color = Some(palette.text);
        style.visuals.weak_text_color = Some(palette.muted);
        style.visuals.selection.bg_fill = palette.accent_soft;
        style.visuals.selection.stroke = Stroke::new(1.0, palette.accent);
        style.visuals.hyperlink_color = palette.blue;
        style.visuals.warn_fg_color = palette.amber;
        style.visuals.error_fg_color = palette.red;
        style.visuals.widgets.noninteractive.bg_fill = palette.raised;
        style.visuals.widgets.noninteractive.bg_stroke = Stroke::new(1.0, palette.stroke);
        style.visuals.widgets.noninteractive.fg_stroke = Stroke::new(1.0, palette.text);
        style.visuals.widgets.inactive.bg_fill = palette.card;
        style.visuals.widgets.inactive.weak_bg_fill = palette.raised;
        style.visuals.widgets.inactive.bg_stroke = Stroke::new(1.0, palette.stroke);
        style.visuals.widgets.inactive.fg_stroke = Stroke::new(1.0, palette.text);
        style.visuals.widgets.hovered.bg_fill = palette.hover;
        style.visuals.widgets.hovered.weak_bg_fill = palette.hover;
        style.visuals.widgets.hovered.bg_stroke = Stroke::new(1.0, palette.muted);
        style.visuals.widgets.hovered.fg_stroke = Stroke::new(1.0, palette.text);
        style.visuals.widgets.active.bg_fill = palette.accent_soft;
        style.visuals.widgets.active.weak_bg_fill = palette.accent_soft;
        style.visuals.widgets.active.bg_stroke = Stroke::new(1.0, palette.accent);
        style.visuals.widgets.active.fg_stroke = Stroke::new(1.0, palette.text);
        style.visuals.widgets.open = style.visuals.widgets.active;
        for visual in [
            &mut style.visuals.widgets.noninteractive,
            &mut style.visuals.widgets.inactive,
            &mut style.visuals.widgets.hovered,
            &mut style.visuals.widgets.active,
            &mut style.visuals.widgets.open,
        ] {
            visual.corner_radius = CornerRadius::same(6);
        }
        style.visuals.window_corner_radius = CornerRadius::same(10);
        style.visuals.menu_corner_radius = CornerRadius::same(8);
        style.visuals.window_shadow = subtle_card_shadow(palette);
        style.visuals.popup_shadow = subtle_card_shadow(palette);
        style.text_styles.insert(
            TextStyle::Heading,
            FontId::new(20.0, FontFamily::Proportional),
        );
        style
            .text_styles
            .insert(TextStyle::Body, FontId::new(13.0, FontFamily::Proportional));
        style.text_styles.insert(
            TextStyle::Button,
            FontId::new(13.0, FontFamily::Proportional),
        );
        style.text_styles.insert(
            TextStyle::Monospace,
            FontId::new(13.0, FontFamily::Monospace),
        );
        style.text_styles.insert(
            TextStyle::Small,
            FontId::new(11.0, FontFamily::Proportional),
        );
        ctx.set_style_of(theme, style);
    }
}

fn configure_fonts(ctx: &egui::Context) {
    let mut fonts = FontDefinitions::default();

    if let Ok(bytes) = std::fs::read("/System/Library/Fonts/SFNS.ttf") {
        fonts.font_data.insert(
            "SF Pro".to_owned(),
            std::sync::Arc::new(FontData::from_owned(bytes)),
        );
        if let Some(family) = fonts.families.get_mut(&FontFamily::Proportional) {
            family.insert(0, "SF Pro".to_owned());
        }
    }

    if let Ok(bytes) = std::fs::read("/System/Library/Fonts/SFNSMono.ttf") {
        fonts.font_data.insert(
            "SF Mono".to_owned(),
            std::sync::Arc::new(FontData::from_owned(bytes)),
        );
        if let Some(family) = fonts.families.get_mut(&FontFamily::Monospace) {
            family.insert(0, "SF Mono".to_owned());
        }
    }

    let serif_family = FontFamily::Name("Statement Serif".into());
    let mut serif_fonts = fonts
        .families
        .get(&FontFamily::Proportional)
        .cloned()
        .unwrap_or_default();
    if let Ok(bytes) = std::fs::read("/System/Library/Fonts/NewYork.ttf") {
        fonts.font_data.insert(
            "New York".to_owned(),
            std::sync::Arc::new(FontData::from_owned(bytes)),
        );
        serif_fonts.insert(0, "New York".to_owned());
    }
    fonts.families.insert(serif_family, serif_fonts);
    ctx.set_fonts(fonts);
}

fn draw_response_editor(
    ui: &mut egui::Ui,
    part: &QuestionPart,
    answer: &mut StudentAnswer,
    palette: Palette,
    editor_scope: &str,
) -> bool {
    match part.kind {
        ResponseKind::SingleChoice => draw_single_choice(ui, part, answer, palette),
        ResponseKind::MultipleChoice => draw_multiple_choice(ui, part, answer, palette),
        ResponseKind::Number => labelled_text_edit(
            ui,
            "Accounting amount or ratio",
            &mut answer.scalar,
            "Examples: 12500, $12,500, (450), or 1.50",
            false,
            true,
        ),
        ResponseKind::Formula => draw_formula_editor(ui, &mut answer.scalar, palette, editor_scope),
        ResponseKind::ShortText => labelled_text_edit(
            ui,
            "Short answer",
            &mut answer.scalar,
            "Enter the requested term or concise response",
            false,
            false,
        ),
        ResponseKind::LongText => labelled_text_edit(
            ui,
            "Written response",
            &mut answer.scalar,
            "Explain your reasoning in complete sentences…",
            true,
            false,
        ),
        ResponseKind::Journal => draw_table_editor(ui, part, answer, palette, true, editor_scope),
        ResponseKind::Table => draw_table_editor(ui, part, answer, palette, false, editor_scope),
        ResponseKind::Matching => draw_matching_editor(ui, part, answer, palette, editor_scope),
        ResponseKind::Ordering => draw_ordering_editor(ui, part, answer, palette),
        ResponseKind::TrueFalse => {
            let mut changed = false;
            ui.horizontal(|ui| {
                changed |= ui
                    .radio_value(&mut answer.scalar, "True".to_owned(), "True")
                    .changed();
                changed |= ui
                    .radio_value(&mut answer.scalar, "False".to_owned(), "False")
                    .changed();
            });
            ui.add_space(8.0);
            changed
                | labelled_text_edit(
                    ui,
                    "Correction or support notes",
                    &mut answer.notes,
                    "If false, correct the assertion; if true, note why.",
                    true,
                    false,
                )
        }
        ResponseKind::NoEntry => {
            let mut changed = false;
            ui.horizontal(|ui| {
                changed |= ui
                    .radio_value(&mut answer.scalar, "Entry".to_owned(), "Entry")
                    .changed();
                changed |= ui
                    .radio_value(&mut answer.scalar, "No entry".to_owned(), "No entry")
                    .changed();
            });
            ui.add_space(8.0);
            changed
                | labelled_text_edit(
                    ui,
                    "Recognition rationale",
                    &mut answer.notes,
                    "Explain why recognition is or is not appropriate.",
                    true,
                    false,
                )
        }
    }
}

fn draw_single_choice(
    ui: &mut egui::Ui,
    part: &QuestionPart,
    answer: &mut StudentAnswer,
    palette: Palette,
) -> bool {
    if part.options.is_empty() {
        return labelled_text_edit(
            ui,
            "Choice ID",
            &mut answer.scalar,
            "Enter the selected choice",
            false,
            false,
        );
    }
    let mut changed = false;
    let selected = answer.selections.first().cloned().unwrap_or_default();
    for option in &part.options {
        let is_selected = selected == option.id;
        let row = Frame::new()
            .fill(if is_selected {
                palette.accent_soft
            } else {
                Color32::TRANSPARENT
            })
            .corner_radius(8)
            .inner_margin(10)
            .show(ui, |ui| {
                ui.set_width(ui.available_width());
                ui.radio(is_selected, format!("{} — {}", option.id, option.text))
            });
        if row.inner.clicked() {
            answer.selections.clear();
            answer.selections.push(option.id.clone());
            changed = true;
        }
        ui.add_space(2.0);
    }
    changed
}

fn draw_multiple_choice(
    ui: &mut egui::Ui,
    part: &QuestionPart,
    answer: &mut StudentAnswer,
    palette: Palette,
) -> bool {
    if part.options.is_empty() {
        return labelled_text_edit(
            ui,
            "Choice IDs",
            &mut answer.scalar,
            "Enter all selected choices",
            false,
            false,
        );
    }
    ui.label(
        RichText::new("Select every answer that applies.")
            .size(11.0)
            .color(palette.muted),
    );
    let mut changed = false;
    for option in &part.options {
        let mut selected = answer.selections.contains(&option.id);
        let response = Frame::new()
            .fill(if selected {
                palette.accent_soft
            } else {
                Color32::TRANSPARENT
            })
            .corner_radius(8)
            .inner_margin(10)
            .show(ui, |ui| {
                ui.set_width(ui.available_width());
                ui.checkbox(&mut selected, format!("{} — {}", option.id, option.text))
            })
            .inner;
        if response.changed() {
            if selected {
                answer.selections.push(option.id.clone());
            } else {
                answer.selections.retain(|id| id != &option.id);
            }
            changed = true;
        }
        ui.add_space(2.0);
    }
    changed
}

fn labelled_text_edit(
    ui: &mut egui::Ui,
    label: &str,
    value: &mut String,
    hint: &str,
    multiline: bool,
    monospace: bool,
) -> bool {
    let label_response = ui.label(
        RichText::new(label)
            .size(10.0)
            .color(ui.visuals().weak_text_color()),
    );
    let mut editor = if multiline {
        TextEdit::multiline(value).desired_rows(8)
    } else {
        TextEdit::singleline(value)
    };
    editor = editor
        .desired_width(f32::INFINITY)
        .hint_text(hint)
        .margin(8);
    if monospace {
        editor = editor.font(TextStyle::Monospace);
    }
    let response = if multiline {
        ui.add_sized([ui.available_width(), 150.0], editor)
    } else {
        ui.add(editor)
    };
    response
        .labelled_by(label_response.id)
        .on_hover_text(label)
        .changed()
}

fn draw_formula_editor(
    ui: &mut egui::Ui,
    value: &mut String,
    palette: Palette,
    editor_scope: &str,
) -> bool {
    let label = ui.label(RichText::new("Formula").size(12.0).strong());
    let response = ui
        .add(
            TextEdit::singleline(value)
                .id_salt(("standalone_formula", editor_scope))
                .desired_width(f32::INFINITY)
                .hint_text("Example: BI + P - EI or =PV(8%,5,0,10000)")
                .margin(Margin::symmetric(10, 8))
                .font(TextStyle::Monospace),
        )
        .labelled_by(label.id)
        .on_hover_text("Enter the requested formula or spreadsheet function");
    let changed = response.changed();
    if value.trim_start().starts_with('=') {
        let preview = evaluate_formula(value);
        let (title, detail, color) = match preview {
            CellValue::Error(error) => ("Preview error", error.to_string(), palette.red),
            value => ("Evaluated preview", value.display_text(), palette.green),
        };
        ui.horizontal_wrapped(|ui| {
            ui.label(RichText::new("=").size(12.0).strong().color(color));
            ui.label(RichText::new(title).size(11.0).strong().color(color));
            ui.label(RichText::new(detail).size(11.0).monospace());
        });
        ui.label(
            RichText::new(
                "The preview evaluates self-contained formulas. Named variables and A1 references require a table-grid context; the authored formula can still be checked as text.",
            )
            .size(10.0)
            .color(palette.muted),
        );
    }
    changed
}

fn draw_table_editor(
    ui: &mut egui::Ui,
    part: &QuestionPart,
    answer: &mut StudentAnswer,
    palette: Palette,
    journal: bool,
    editor_scope: &str,
) -> bool {
    let default_columns = if journal {
        vec![
            "Account".to_owned(),
            "Debit".to_owned(),
            "Credit".to_owned(),
        ]
    } else {
        vec!["Item".to_owned(), "Amount".to_owned()]
    };
    let minimum_columns = if part.columns.is_empty() {
        default_columns.len()
    } else {
        part.columns.len()
    };
    let column_count = part
        .columns
        .len()
        .max(part.expected.rows.iter().map(Vec::len).max().unwrap_or(0))
        .max(answer.rows.iter().map(Vec::len).max().unwrap_or(0))
        .max(minimum_columns);
    let mut columns = if part.columns.is_empty() {
        default_columns
    } else {
        part.columns.clone()
    };
    while columns.len() < column_count {
        columns.push(format!("Column {}", columns.len() + 1));
    }
    let mut changed = false;
    if answer.rows.is_empty() {
        let initial_rows = part.expected.rows.len().max(2);
        answer.rows = vec![vec![String::new(); column_count]; initial_rows];
        changed = true;
    }
    for row in &mut answer.rows {
        if row.len() < column_count {
            row.resize(column_count, String::new());
            changed = true;
        }
    }
    let evaluated = evaluate_grid(&answer.rows);

    ui.label(
        RichText::new(if journal {
            "▤  Journal Entry"
        } else {
            "▦  Accounting Schedule"
        })
        .size(12.0)
        .strong(),
    );
    ui.label(
        RichText::new(if journal {
            "Enter one account per row. Blank debit or credit cells are allowed. Start a calculation with =; its evaluated result appears below the raw formula."
        } else {
            "Complete the grid and add or remove rows as needed. Start a calculation with =; A1 references and evaluated results work like a compact spreadsheet."
        })
        .size(12.0)
        .color(palette.muted),
    );
    ui.label(
        RichText::new("Functions: SUM, AVERAGE, MIN, MAX, ROUND, ABS, IF, PV, FV, PMT, and NPV.")
            .size(11.0)
            .color(palette.muted),
    );
    let mut remove_row = None;
    let can_remove = answer.rows.len() > 1;
    Frame::new()
        .fill(palette.card)
        .stroke(Stroke::new(1.0, palette.stroke))
        .corner_radius(8)
        .inner_margin(10)
        .show(ui, |ui| {
            ScrollArea::horizontal()
                .id_salt(("response_grid_scroll", editor_scope))
                .auto_shrink([false, true])
                .show(ui, |ui| {
                    let cell_width = if journal { 155.0 } else { 138.0 };
                    Grid::new(("response_grid", editor_scope))
                        .num_columns(columns.len() + 2)
                        .min_col_width(48.0)
                        .min_row_height(40.0)
                        .spacing(Vec2::new(7.0, 7.0))
                        .striped(true)
                        .show(ui, |ui| {
                            ui.label(
                                RichText::new("Row")
                                    .size(11.0)
                                    .strong()
                                    .color(palette.muted),
                            );
                            let header_ids = columns
                                .iter()
                                .map(|column| {
                                    ui.label(
                                        RichText::new(column)
                                            .size(11.0)
                                            .strong()
                                            .color(palette.muted),
                                    )
                                    .id
                                })
                                .collect::<Vec<_>>();
                            ui.label("");
                            ui.end_row();

                            for (row_index, row) in answer.rows.iter_mut().enumerate() {
                                ui.label(
                                    RichText::new((row_index + 1).to_string())
                                        .color(palette.muted)
                                        .monospace(),
                                );
                                for (column_index, cell) in row.iter_mut().enumerate() {
                                    let evaluated_cell = evaluated
                                        .get(row_index)
                                        .and_then(|row| row.get(column_index));
                                    ui.vertical(|ui| {
                                        let response = ui
                                            .add_sized(
                                                [cell_width, 32.0],
                                                TextEdit::singleline(cell)
                                                    .id_salt((
                                                        editor_scope,
                                                        row_index,
                                                        column_index,
                                                    ))
                                                    .font(if column_index == 0 {
                                                        TextStyle::Body
                                                    } else {
                                                        TextStyle::Monospace
                                                    })
                                                    .hint_text(if column_index == 0 {
                                                        "Label or =formula"
                                                    } else {
                                                        "Value or =formula"
                                                    }),
                                            )
                                            .labelled_by(header_ids[column_index]);
                                        changed |= response.changed();
                                        if cell.trim_start().starts_with('=')
                                            && let Some(evaluated_cell) = evaluated_cell
                                        {
                                            let (result, color) = match evaluated_cell {
                                                CellValue::Error(error) => {
                                                    (error.to_string(), palette.red)
                                                }
                                                value => (
                                                    format!("Result: {}", value.display_text()),
                                                    palette.accent,
                                                ),
                                            };
                                            ui.add(
                                                Label::new(
                                                    RichText::new(result)
                                                        .size(10.0)
                                                        .monospace()
                                                        .color(color),
                                                )
                                                .truncate(),
                                            );
                                        }
                                    });
                                }
                                let remove_label = format!("Remove row {}", row_index + 1);
                                if ui
                                    .add_enabled(can_remove, Button::new("−").small())
                                    .on_hover_text(&remove_label)
                                    .clicked()
                                {
                                    remove_row = Some(row_index);
                                }
                                ui.end_row();
                            }
                        });
                });
        });
    if let Some(index) = remove_row {
        answer.rows.remove(index);
        changed = true;
    }
    if ui
        .button("+  Add Row")
        .on_hover_text("Append a blank row to this response")
        .clicked()
    {
        answer.rows.push(vec![String::new(); columns.len()]);
        changed = true;
    }
    changed
}

fn draw_matching_editor(
    ui: &mut egui::Ui,
    part: &QuestionPart,
    answer: &mut StudentAnswer,
    palette: Palette,
    editor_scope: &str,
) -> bool {
    if part.items.is_empty() || part.targets.is_empty() {
        warning_card(
            ui,
            "This matching part is missing Items or Targets metadata. Enter a manual mapping below.",
            palette,
        );
        return labelled_text_edit(
            ui,
            "Manual mapping",
            &mut answer.scalar,
            "item => target",
            true,
            true,
        );
    }
    let mut changed = false;
    Grid::new(("matching", editor_scope))
        .num_columns(2)
        .min_col_width(120.0)
        .spacing(Vec2::new(12.0, 9.0))
        .striped(true)
        .show(ui, |ui| {
            ui.label(
                RichText::new("Item")
                    .size(11.0)
                    .strong()
                    .color(palette.muted),
            );
            ui.label(
                RichText::new("Classification / match")
                    .size(11.0)
                    .strong()
                    .color(palette.muted),
            );
            ui.end_row();
            for item in &part.items {
                let item_label = ui.label(&item.text);
                let current = answer.pairs.get(&item.id).cloned().unwrap_or_default();
                let selected_text = part
                    .targets
                    .iter()
                    .find(|target| target.id == current)
                    .map_or("Choose…", |target| target.text.as_str());
                let mut next = current.clone();
                let response = ComboBox::from_id_salt((editor_scope, &item.id))
                    .selected_text(selected_text)
                    .width(190.0)
                    .show_ui(ui, |ui| {
                        for target in &part.targets {
                            if ui
                                .selectable_label(next == target.id, &target.text)
                                .clicked()
                            {
                                next.clone_from(&target.id);
                            }
                        }
                    })
                    .response
                    .labelled_by(item_label.id);
                if next != current {
                    answer.pairs.insert(item.id.clone(), next);
                    changed = true;
                }
                response.on_hover_text(format!("Choose a match for {}", item.text));
                ui.end_row();
            }
        });
    changed
}

fn draw_ordering_editor(
    ui: &mut egui::Ui,
    part: &QuestionPart,
    answer: &mut StudentAnswer,
    palette: Palette,
) -> bool {
    if part.items.is_empty() {
        return labelled_text_edit(
            ui,
            "Ordered sequence",
            &mut answer.scalar,
            "Enter one item per line in the required order",
            true,
            false,
        );
    }
    let shown_order = part
        .items
        .iter()
        .map(|item| item.id.clone())
        .collect::<Vec<_>>();
    let mut changed = false;
    let mut working_order = if answer.order.is_empty() {
        shown_order.clone()
    } else {
        answer.order.clone()
    };
    working_order.retain(|id| part.items.iter().any(|item| &item.id == id));
    for id in &shown_order {
        if !working_order.contains(id) {
            working_order.push(id.clone());
        }
    }

    ui.label(
        RichText::new("Move the items until the required sequence runs from top to bottom.")
            .size(12.0)
            .color(palette.muted),
    );
    let mut move_action: Option<(usize, isize)> = None;
    for (index, id) in working_order.iter().enumerate() {
        let label = part
            .items
            .iter()
            .find(|item| &item.id == id)
            .map_or(id.as_str(), |item| item.text.as_str());
        Frame::new()
            .fill(palette.raised)
            .stroke(Stroke::new(1.0, palette.stroke))
            .corner_radius(9)
            .inner_margin(9)
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    Frame::new()
                        .fill(palette.accent_soft)
                        .corner_radius(7)
                        .inner_margin(Margin::symmetric(9, 5))
                        .show(ui, |ui| {
                            ui.label(
                                RichText::new((index + 1).to_string())
                                    .strong()
                                    .color(palette.accent)
                                    .monospace(),
                            );
                        });
                    ui.add(Label::new(label).wrap());
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if ui
                            .add_enabled(index + 1 < working_order.len(), Button::new("Move down"))
                            .clicked()
                        {
                            move_action = Some((index, 1));
                        }
                        if ui.add_enabled(index > 0, Button::new("Move up")).clicked() {
                            move_action = Some((index, -1));
                        }
                    });
                });
            });
        ui.add_space(4.0);
    }
    if let Some((index, delta)) = move_action {
        let other = (index as isize + delta) as usize;
        working_order.swap(index, other);
        answer.order = working_order;
        changed = true;
    }
    if ui
        .small_button("Reset to the shown order")
        .on_hover_text("Restore the original item order")
        .clicked()
    {
        answer.order = shown_order;
        changed = true;
    }
    changed
}

fn show_expected_answer(ui: &mut egui::Ui, part: &QuestionPart, palette: Palette) {
    match part.kind {
        ResponseKind::SingleChoice | ResponseKind::MultipleChoice => {
            for id in &part.expected.selections {
                let text = part
                    .options
                    .iter()
                    .find(|option| &option.id == id)
                    .map_or("", |option| option.text.as_str());
                ui.label(RichText::new(format!("{id} — {text}")).strong());
            }
        }
        ResponseKind::Journal | ResponseKind::Table => {
            show_read_only_rows(ui, &part.columns, &part.expected.rows, palette);
        }
        ResponseKind::Matching => {
            for item in &part.items {
                if let Some(target_id) = part.expected.pairs.get(&item.id) {
                    let target = part
                        .targets
                        .iter()
                        .find(|target| &target.id == target_id)
                        .map_or(target_id.as_str(), |target| target.text.as_str());
                    ui.label(format!("{} → {target}", item.text));
                }
            }
        }
        ResponseKind::Ordering => {
            for (index, id) in part.expected.order.iter().enumerate() {
                let label = part
                    .items
                    .iter()
                    .find(|item| &item.id == id)
                    .map_or(id.as_str(), |item| item.text.as_str());
                ui.label(format!("{}. {label}", index + 1));
            }
        }
        _ => {
            if part.expected.scalar.trim().is_empty() {
                let message = if part.rubric_markdown.trim().is_empty() {
                    "No model answer or rubric was supplied; this part remains unverified."
                } else {
                    "Use the rubric below to evaluate this response."
                };
                ui.label(RichText::new(message).color(palette.muted));
            } else if part.kind == ResponseKind::Formula || part.kind == ResponseKind::Number {
                ui.label(
                    RichText::new(&part.expected.scalar)
                        .size(16.0)
                        .strong()
                        .monospace(),
                );
            } else {
                render_markdown(ui, &part.expected.scalar, palette, 14.0);
            }
            if !part.expected.accepted.is_empty() {
                ui.add_space(6.0);
                ui.label(
                    RichText::new(format!(
                        "Also accepted: {}",
                        part.expected.accepted.join(" · ")
                    ))
                    .size(11.0)
                    .color(palette.muted),
                );
            }
        }
    }
}

fn show_read_only_rows(
    ui: &mut egui::Ui,
    configured_columns: &[String],
    rows: &[Vec<String>],
    palette: Palette,
) {
    let column_count = configured_columns
        .len()
        .max(rows.iter().map(Vec::len).max().unwrap_or(0));
    if column_count == 0 {
        ui.label(RichText::new("No tabular answer supplied.").color(palette.muted));
        return;
    }
    let columns = (0..column_count)
        .map(|index| {
            configured_columns
                .get(index)
                .cloned()
                .unwrap_or_else(|| format!("Column {}", index + 1))
        })
        .collect::<Vec<_>>();
    ScrollArea::horizontal().show(ui, |ui| {
        Grid::new(("answer_rows", configured_columns.join("|")))
            .num_columns(column_count)
            .striped(true)
            .spacing(Vec2::new(14.0, 7.0))
            .show(ui, |ui| {
                for column in &columns {
                    ui.label(
                        RichText::new(column)
                            .size(11.0)
                            .strong()
                            .color(palette.muted),
                    );
                }
                ui.end_row();
                for row in rows {
                    for index in 0..column_count {
                        ui.label(
                            RichText::new(row.get(index).map_or("", String::as_str)).monospace(),
                        );
                    }
                    ui.end_row();
                }
            });
    });
}

fn library_question_row(
    ui: &mut egui::Ui,
    item: &LibraryQuestion,
    selected: bool,
    palette: Palette,
) -> bool {
    let (status_color, status_label) = match item.progress {
        QuestionProgress::NotStarted => (palette.muted, "Not started"),
        QuestionProgress::InProgress => (palette.amber, "In progress"),
        QuestionProgress::Complete => (palette.green, "Mastered"),
    };
    let desired_size = Vec2::new(ui.available_width(), 80.0);
    let (rect, response) = ui.allocate_exact_size(desired_size, Sense::click());
    let row_rect = rect.shrink2(Vec2::new(0.0, 2.0));
    let fill = if selected {
        palette.accent
    } else if response.hovered() {
        palette.hover
    } else {
        Color32::TRANSPARENT
    };
    ui.painter().rect_filled(row_rect, 8, fill);
    if response.has_focus() {
        ui.painter().rect_stroke(
            row_rect,
            8,
            Stroke::new(
                1.5,
                if selected {
                    palette.on_accent
                } else {
                    palette.accent
                },
            ),
            egui::StrokeKind::Inside,
        );
    }

    let content_rect = row_rect.shrink2(Vec2::new(10.0, 6.0));
    let mut row_ui = ui.new_child(
        UiBuilder::new()
            .max_rect(content_rect)
            .layout(Layout::left_to_right(Align::Min)),
    );
    row_ui.set_clip_rect(ui.clip_rect().intersect(row_rect));
    let primary = if selected {
        palette.on_accent
    } else {
        palette.text
    };
    let secondary = if selected {
        Color32::from_rgba_unmultiplied(255, 255, 255, 215)
    } else {
        palette.muted
    };
    row_ui.spacing_mut().item_spacing.x = 10.0;
    let icon_color = if selected {
        palette.on_accent
    } else {
        status_color
    };
    let (icon_rect, _) = row_ui.allocate_exact_size(Vec2::new(16.0, 19.0), Sense::hover());
    paint_library_icon(
        row_ui.painter(),
        icon_rect,
        item.progress == QuestionProgress::Complete,
        icon_color,
    );
    row_ui.vertical(|ui| {
        ui.set_width(ui.available_width());
        ui.spacing_mut().item_spacing.y = 5.0;
        ui.add(
            Label::new(
                RichText::new(elide_for_two_lines(&item.title, 50))
                    .size(13.0)
                    .color(primary),
            )
            .wrap(),
        );
        ui.label(
            RichText::new(format!(
                "{}  •  {}/{}",
                shell_label(item.shell),
                item.answered_parts,
                item.total_parts
            ))
            .size(10.0)
            .color(secondary),
        );
        let fraction = if item.total_parts == 0 {
            0.0
        } else {
            item.answered_parts as f32 / item.total_parts as f32
        };
        ui.add(
            ProgressBar::new(fraction)
                .desired_width(ui.available_width())
                .desired_height(3.0)
                .fill(if selected {
                    palette.on_accent
                } else if item.progress == QuestionProgress::Complete {
                    palette.green
                } else {
                    palette.accent
                }),
        );
    });

    let response = response.on_hover_text(format!(
        "Open {} from {} — {}",
        item.title, item.pack_title, status_label
    ));
    response.widget_info(|| {
        WidgetInfo::labeled(
            WidgetType::Button,
            true,
            format!(
                "Open {} from {}: {status_label}",
                item.title, item.pack_title
            ),
        )
    });
    response.clicked()
}

fn elide_for_two_lines(text: &str, max_characters: usize) -> String {
    if text.chars().count() <= max_characters {
        return text.to_owned();
    }
    let mut result = text
        .chars()
        .take(max_characters.saturating_sub(1))
        .collect::<String>();
    result.push('…');
    result
}

fn paint_library_icon(painter: &egui::Painter, rect: egui::Rect, complete: bool, color: Color32) {
    let stroke = Stroke::new(1.35, color);
    if complete {
        painter.circle_stroke(rect.center(), 6.5, stroke);
        painter.add(egui::Shape::line(
            vec![
                egui::pos2(rect.center().x - 3.2, rect.center().y),
                egui::pos2(rect.center().x - 0.8, rect.center().y + 2.6),
                egui::pos2(rect.center().x + 4.0, rect.center().y - 3.0),
            ],
            stroke,
        ));
    } else {
        let page = rect.shrink2(Vec2::new(2.0, 1.0));
        painter.rect_stroke(page, 1.5, stroke, egui::StrokeKind::Inside);
        painter.line_segment(
            [
                egui::pos2(page.left() + 3.0, page.center().y - 1.0),
                egui::pos2(page.right() - 3.0, page.center().y - 1.0),
            ],
            stroke,
        );
        painter.line_segment(
            [
                egui::pos2(page.left() + 3.0, page.center().y + 3.0),
                egui::pos2(page.right() - 3.0, page.center().y + 3.0),
            ],
            stroke,
        );
    }
}

fn paint_filter_control(painter: &egui::Painter, rect: egui::Rect, expanded: bool, color: Color32) {
    let stroke = Stroke::new(1.25, color);
    let x = rect.left() + 7.0;
    let center_y = rect.center().y;
    for (offset, width) in [(-4.0, 10.0), (0.0, 7.0), (4.0, 4.0)] {
        painter.line_segment(
            [
                egui::pos2(x, center_y + offset),
                egui::pos2(x + width, center_y + offset),
            ],
            stroke,
        );
    }
    let caret_x = rect.right() - 7.0;
    let direction = if expanded { -1.0 } else { 1.0 };
    painter.add(egui::Shape::line(
        vec![
            egui::pos2(caret_x - 2.5, center_y - direction),
            egui::pos2(caret_x, center_y + direction * 1.5),
            egui::pos2(caret_x + 2.5, center_y - direction),
        ],
        stroke,
    ));
}

fn empty_library_card(ui: &mut egui::Ui, palette: Palette) {
    ui.add_space(16.0);
    Frame::new()
        .fill(palette.card)
        .stroke(Stroke::new(1.0, palette.stroke))
        .corner_radius(10)
        .inner_margin(16)
        .show(ui, |ui| {
            ui.label(RichText::new("No matching questions").strong());
            ui.label(
                RichText::new("Clear a filter or import another Markdown pack.")
                    .size(12.0)
                    .color(palette.muted),
            );
        });
}

fn warning_card(ui: &mut egui::Ui, message: &str, palette: Palette) {
    Frame::new()
        .fill(palette.amber_soft)
        .stroke(Stroke::new(1.0, palette.amber))
        .corner_radius(9)
        .inner_margin(12)
        .show(ui, |ui| {
            ui.label(RichText::new(message).color(palette.text));
        });
}

fn chip(ui: &mut egui::Ui, text: impl Into<RichText>, fill: Color32, foreground: Color32) {
    Frame::new()
        .fill(fill)
        .corner_radius(99)
        .inner_margin(Margin::symmetric(9, 4))
        .show(ui, |ui| {
            let text: RichText = text.into();
            ui.label(text.size(10.5).strong().color(foreground));
        });
}

fn inspector_section_title(ui: &mut egui::Ui, text: &str, palette: Palette) {
    ui.label(RichText::new(text).size(11.0).strong().color(palette.text));
    ui.add_space(3.0);
}

fn inspector_value_row(
    ui: &mut egui::Ui,
    label: &str,
    value: &str,
    palette: Palette,
    monospace: bool,
) {
    ui.horizontal(|ui| {
        ui.label(RichText::new(label).size(12.0).color(palette.muted));
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            let text = RichText::new(if value.trim().is_empty() {
                "Unknown"
            } else {
                value
            })
            .size(12.0)
            .color(palette.text);
            ui.add(Label::new(if monospace { text.monospace() } else { text }).truncate());
        });
    });
}

fn grade_banner(ui: &mut egui::Ui, result: &GradeResult, palette: Palette) {
    let (color, soft, icon, title) = match result.status {
        GradeStatus::Correct => (palette.green, palette.green_soft, "✓", "Correct"),
        GradeStatus::Incorrect => (palette.red, palette.red_soft, "×", "Not correct yet"),
        GradeStatus::NeedsSelfReview => {
            (palette.amber, palette.amber_soft, "!", "Self-review needed")
        }
        GradeStatus::Unverified => (palette.blue, palette.raised, "?", "Unverified source item"),
        GradeStatus::Unanswered => (palette.muted, palette.raised, "○", "Response needed"),
    };
    Frame::new()
        .fill(soft)
        .corner_radius(9)
        .inner_margin(10)
        .show(ui, |ui| {
            ui.set_width(ui.available_width());
            ui.horizontal_top(|ui| {
                ui.label(RichText::new(icon).size(15.0).strong().color(color));
                ui.vertical(|ui| {
                    ui.set_width(ui.available_width());
                    ui.label(RichText::new(title).size(12.0).strong().color(color));
                    ui.add(
                        Label::new(
                            RichText::new(&result.feedback)
                                .size(11.0)
                                .color(palette.text),
                        )
                        .wrap(),
                    );
                });
            });
        });
}

fn grade_status_style(status: GradeStatus, palette: Palette) -> (Color32, &'static str) {
    match status {
        GradeStatus::Correct => (palette.green, "Mastered"),
        GradeStatus::Incorrect => (palette.red, "Try again"),
        GradeStatus::NeedsSelfReview => (palette.amber, "Review"),
        GradeStatus::Unverified => (palette.blue, "Unverified"),
        GradeStatus::Unanswered => (palette.muted, "Unanswered"),
    }
}

fn render_markdown(ui: &mut egui::Ui, markdown: &str, palette: Palette, body_size: f32) {
    ui.scope(|ui| {
        ui.spacing_mut().item_spacing.y = 4.0;
        for line in markdown.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                ui.add_space(6.0);
                continue;
            }
            if let Some(heading) = trimmed.strip_prefix("### ") {
                ui.label(
                    RichText::new(clean_inline_markdown(heading))
                        .font(markdown_font(body_size + 2.0))
                        .strong(),
                );
            } else if let Some(heading) = trimmed.strip_prefix("## ") {
                ui.label(
                    RichText::new(clean_inline_markdown(heading))
                        .font(markdown_font(body_size + 4.0))
                        .strong(),
                );
            } else if let Some(heading) = trimmed.strip_prefix("# ") {
                ui.label(
                    RichText::new(clean_inline_markdown(heading))
                        .font(markdown_font(body_size + 6.0))
                        .strong(),
                );
            } else if let Some(item) = trimmed
                .strip_prefix("- ")
                .or_else(|| trimmed.strip_prefix("* "))
            {
                ui.horizontal_wrapped(|ui| {
                    ui.label(RichText::new("•").color(palette.accent));
                    ui.add(Label::new(markdown_layout_job(item, palette, body_size)).wrap());
                });
            } else if trimmed.starts_with('|') {
                ui.add(
                    Label::new(
                        RichText::new(trimmed)
                            .size(body_size - 1.0)
                            .monospace()
                            .color(palette.text),
                    )
                    .wrap(),
                );
            } else {
                ui.add(Label::new(markdown_layout_job(trimmed, palette, body_size)).wrap());
            }
        }
    });
}

fn markdown_layout_job(value: &str, palette: Palette, body_size: f32) -> egui::text::LayoutJob {
    let mut job = egui::text::LayoutJob::default();
    let mut remainder = value;
    while !remainder.is_empty() {
        let next = ["**", "__", "`"]
            .into_iter()
            .filter_map(|marker| remainder.find(marker).map(|position| (position, marker)))
            .min_by_key(|(position, _)| *position);
        let Some((position, marker)) = next else {
            append_markdown_span(&mut job, remainder, palette, body_size, false, false);
            break;
        };
        if position > 0 {
            append_markdown_span(
                &mut job,
                &remainder[..position],
                palette,
                body_size,
                false,
                false,
            );
            remainder = &remainder[position..];
            continue;
        }
        let content = &remainder[marker.len()..];
        let Some(close) = content.find(marker) else {
            append_markdown_span(&mut job, marker, palette, body_size, false, false);
            remainder = content;
            continue;
        };
        let span = &content[..close];
        let is_code = marker == "`";
        append_markdown_span(
            &mut job,
            span,
            palette,
            if marker.len() == 2 {
                body_size + 0.2
            } else {
                body_size
            },
            false,
            is_code,
        );
        remainder = &content[close + marker.len()..];
    }
    job
}

fn append_markdown_span(
    job: &mut egui::text::LayoutJob,
    text: &str,
    palette: Palette,
    size: f32,
    italics: bool,
    code: bool,
) {
    let font_id = if code {
        FontId::new(size - 0.5, FontFamily::Monospace)
    } else {
        markdown_font(size)
    };
    job.append(
        text,
        0.0,
        egui::TextFormat {
            font_id,
            line_height: Some(size + 4.0),
            color: palette.text,
            background: if code {
                palette.raised
            } else {
                Color32::TRANSPARENT
            },
            italics,
            ..Default::default()
        },
    );
}

fn markdown_font(size: f32) -> FontId {
    FontId::new(size, FontFamily::Name("Statement Serif".into()))
}

fn clean_inline_markdown(value: &str) -> String {
    value.replace("**", "").replace("__", "").replace('`', "")
}

fn humanize(value: &str) -> String {
    let mut words = value.split('_');
    let first = words.next().unwrap_or_default();
    let mut result = String::new();
    if let Some(initial) = first.chars().next() {
        result.extend(initial.to_uppercase());
        result.push_str(&first[initial.len_utf8()..]);
    }
    for word in words {
        result.push(' ');
        result.push_str(word);
    }
    result
}

fn shell_label(shell: QuestionShell) -> &'static str {
    match shell {
        QuestionShell::MultipleChoice => "Multiple choice",
        QuestionShell::StandaloneCalculation => "Standalone calculation",
        QuestionShell::Multipart => "Multipart problem",
        QuestionShell::MultipleCase => "Multiple-case problem",
        QuestionShell::Lifecycle => "Lifecycle problem",
        QuestionShell::Comprehensive => "Comprehensive case",
        QuestionShell::MemoResearch => "Memo / research",
    }
}

fn response_kind_label(kind: ResponseKind) -> &'static str {
    match kind {
        ResponseKind::SingleChoice => "Single choice",
        ResponseKind::MultipleChoice => "Select all",
        ResponseKind::Number => "Number",
        ResponseKind::Formula => "Formula",
        ResponseKind::ShortText => "Short text",
        ResponseKind::LongText => "Written response",
        ResponseKind::Journal => "Journal entry",
        ResponseKind::Table => "Working table",
        ResponseKind::Matching => "Matching",
        ResponseKind::Ordering => "Ordering",
        ResponseKind::TrueFalse => "True / false",
        ResponseKind::NoEntry => "Entry decision",
    }
}

fn format_label(format: QuestionFormat) -> &'static str {
    match format {
        QuestionFormat::SingleNumber => "Single-number computation",
        QuestionFormat::FormulaSetup => "Formula setup",
        QuestionFormat::InitialJournalEntry => "Initial-recognition journal entry",
        QuestionFormat::AdjustingJournalEntry => "Adjusting journal entry",
        QuestionFormat::CorrectingJournalEntry => "Correcting journal entry",
        QuestionFormat::ClosingReversingEntry => "Closing or reversing entry",
        QuestionFormat::SettlementEntry => "Settlement or disposal entry",
        QuestionFormat::EntryOrNoEntry => "Entry-or-no-entry decision",
        QuestionFormat::MultiPeriodSchedule => "Multi-period schedule",
        QuestionFormat::Rollforward => "Beginning-to-ending rollforward",
        QuestionFormat::TAccount => "T-account / ledger reconstruction",
        QuestionFormat::Backsolve => "Missing-amount back-solving",
        QuestionFormat::WorksheetTrialBalance => "Worksheet / trial balance",
        QuestionFormat::FullStatement => "Full financial statement",
        QuestionFormat::PartialStatement => "Partial statement excerpt",
        QuestionFormat::PresentationClassificationGrid => "Presentation / classification grid",
        QuestionFormat::EffectMatrix => "Overstated-understated effect matrix",
        QuestionFormat::IncludeExcludeTable => "Include-or-exclude table",
        QuestionFormat::DisclosureDrafting => "Disclosure or footnote drafting",
        QuestionFormat::ReconciliationProof => "Reconciliation / proof / tie-out",
        QuestionFormat::ErrorCorrection => "Error identification and correction",
        QuestionFormat::CorrectVersusIncorrect => "Correct-versus-incorrect comparison",
        QuestionFormat::AlternativeMethodComparison => "Alternative-method comparison",
        QuestionFormat::SensitivityChangedFact => "Sensitivity / changed-fact analysis",
        QuestionFormat::ThresholdCriteriaTest => "Threshold or criteria test",
        QuestionFormat::RankingSequentialInclusion => "Ranking / sequential inclusion",
        QuestionFormat::OrderingTimeline => "Ordering / timeline reconstruction",
        QuestionFormat::RatioAnalysis => "Ratio analysis",
        QuestionFormat::ShortExplanation => "Short explanation",
        QuestionFormat::ClaimEvaluation => "Claim or assertion evaluation",
        QuestionFormat::TrueFalseCorrection => "True / false with correction",
        QuestionFormat::MatchingMappingSorting => "Matching / mapping / sorting",
        QuestionFormat::CodificationResearch => "Codification research",
        QuestionFormat::AisSourceDocumentFlow => "AIS source-document flow",
        QuestionFormat::MultipleChoice => "Multiple choice",
    }
}

fn trim_points(points: f64) -> String {
    let points = if points == 0.0 { 0.0 } else { points };
    if points.fract().abs() < f64::EPSILON {
        format!("{points:.0}")
    } else {
        format!("{points:.1}")
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use accounting_question_core::{
        BUILT_IN_SAMPLE, BUILT_IN_SAMPLE_NAME, ExpectedAnswer, QuestionOption, parse_markdown,
    };

    use super::*;

    #[test]
    fn markdown_layout_preserves_accounting_identifiers_and_formats_code() {
        let palette = Palette::for_dark(false, false);
        let source = "ACCOUNT343_TWO_PER_CONCEPT.md uses `core_000_q2` and **verified** facts";
        let job = markdown_layout_job(source, palette, 13.0);
        assert_eq!(
            job.text,
            "ACCOUNT343_TWO_PER_CONCEPT.md uses core_000_q2 and verified facts"
        );
        assert!(job.sections.iter().any(|section| {
            section.format.font_id.family == FontFamily::Monospace
                && section.format.background == palette.raised
        }));
    }

    #[test]
    fn sidebar_elision_is_unicode_safe_and_bounded() {
        let title = "A very long accounting title with café values and lifecycle requirements";
        let elided = elide_for_two_lines(title, 32);
        assert_eq!(elided.chars().count(), 32);
        assert!(elided.ends_with('…'));
    }

    #[test]
    fn every_response_editor_renders_the_complete_sample_pack() {
        let pack = parse_markdown(BUILT_IN_SAMPLE, BUILT_IN_SAMPLE_NAME)
            .unwrap()
            .pack;
        let mut rendered_kinds = BTreeSet::new();
        for part in pack
            .questions
            .iter()
            .flat_map(|question| question.parts.iter())
        {
            rendered_kinds.insert(part.kind.as_str());
            let mut answer = StudentAnswer::default();
            egui::__run_test_ui(|ui| {
                let _ = draw_response_editor(
                    ui,
                    part,
                    &mut answer,
                    Palette::for_dark(false, false),
                    "headless-editor",
                );
            });
        }
        assert_eq!(rendered_kinds.len(), ResponseKind::ALL.len());
    }

    #[test]
    fn grid_render_keeps_raw_formulas_and_never_truncates_wide_rows() {
        let part = QuestionPart {
            id: "wide-grid".to_owned(),
            kind: ResponseKind::Table,
            columns: vec!["Configured".to_owned()],
            expected: ExpectedAnswer {
                rows: vec![vec!["1".to_owned(), "2".to_owned(), "3".to_owned()]],
                ..ExpectedAnswer::default()
            },
            ..QuestionPart::default()
        };
        let mut answer = StudentAnswer {
            rows: vec![vec![
                "1".to_owned(),
                "=A1+1".to_owned(),
                "3".to_owned(),
                "4".to_owned(),
                "5".to_owned(),
            ]],
            ..StudentAnswer::default()
        };
        egui::__run_test_ui(|ui| {
            let _ = draw_response_editor(
                ui,
                &part,
                &mut answer,
                Palette::for_dark(false, false),
                "wide-grid-test",
            );
        });
        assert_eq!(answer.rows[0].len(), 5);
        assert_eq!(answer.rows[0][1], "=A1+1");
    }

    #[test]
    fn standalone_formula_preview_renders_values_and_errors_without_mutating_answers() {
        for formula in ["=PV(8%,5,0,10000)", "=1/0"] {
            let mut answer = StudentAnswer {
                scalar: formula.to_owned(),
                ..StudentAnswer::default()
            };
            egui::__run_test_ui(|ui| {
                let changed = draw_formula_editor(
                    ui,
                    &mut answer.scalar,
                    Palette::for_dark(false, false),
                    formula,
                );
                assert!(!changed);
            });
            assert_eq!(answer.scalar, formula);
        }

        assert!(matches!(
            evaluate_formula("=PV(8%,5,0,10000)"),
            CellValue::Number(_)
        ));
        assert!(matches!(evaluate_formula("=1/0"), CellValue::Error(_)));
    }

    #[test]
    fn merely_viewing_an_ordering_editor_does_not_submit_an_answer() {
        let part = QuestionPart {
            id: "order".to_owned(),
            kind: ResponseKind::Ordering,
            items: vec![
                QuestionOption::new("first", "First"),
                QuestionOption::new("second", "Second"),
            ],
            expected: ExpectedAnswer {
                order: vec!["second".to_owned(), "first".to_owned()],
                ..ExpectedAnswer::default()
            },
            ..QuestionPart::default()
        };
        let mut answer = StudentAnswer::default();
        egui::__run_test_ui(|ui| {
            let changed = draw_response_editor(
                ui,
                &part,
                &mut answer,
                Palette::for_dark(false, false),
                "ordering-test",
            );
            assert!(!changed);
        });
        assert!(answer.order.is_empty());
        assert!(answer.is_blank());
    }

    #[test]
    fn transient_review_keys_are_pack_scoped() {
        assert_ne!(
            AccountingQuestionStudio::part_key("pack-a", "same", "a"),
            AccountingQuestionStudio::part_key("pack-b", "same", "a")
        );
    }

    #[test]
    fn points_formatting_normalizes_signed_zero() {
        assert_eq!(trim_points(-0.0), "0");
        assert_eq!(trim_points(0.0), "0");
    }
}
