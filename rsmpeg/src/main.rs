#![windows_subsystem = "windows"]

//// TODO TODO TODO
// 
// NEXT: third write of the whole thing? with MPWindowHolder system
// => bof
// 
// Goals:
// - finish rewrite (make it more efficient and more readable)
//   - finish ui (rewrite) //ok
//   - make open/choose buttons work //ok
//   - make format menu apply file extention //ok
//   - generate command (self.ffcmd.gen_cmd()) //ok
//   => make the whole thing work with generated mode //kof ok
//   - feature: once ffcmd-child/job finished, write sdtout/err to collapsed area in exit-status window
//      >> Chorus <<
//   + clean the code fl &str / String
//   + trait to_str ?:: //bof
// - mainw/files/textedit: use .hint_text() and not Option<T> ?::
// - enhance with advanced and manual modes
//      >> Chorus <<
// - eventually add options and languages
//      >> Chorus <<
// 
// Chorus:
// - make it work nice <-----.
// - debug it once           |
// - error handling          |
// - unspaghettify the code  |
// - restart here -----------'

use eframe::egui;
use rfd::FileDialog;
use strum::IntoEnumIterator;
use strum_macros::EnumIter;

use std::path::PathBuf;
use std::process::Command;
use std::io::BufRead;

static VERSION: &str = "0.2.4";
static STATE: &str = "beta";
static ATTR: &'static [&'static str] = &["debug", "unopt", "partial", "EN"];
//static ATTR: &'static [&'static str] = &["release", "partial", "EN"];

macro_rules! mono_text {
    ($e:expr, $self:ident) => {
        egui::RichText::new($e)
            .font($self.config.font_mono.clone())
    };
}

macro_rules! prop_text {
    ($e:expr, $self:ident) => {
        egui::RichText::new($e)
            .font($self.config.font_prop.clone())
    };
}

macro_rules! small_prop_text {
    ($e:expr, $self:ident) => {
        egui::RichText::new($e)
            .font($self.config.font_small_prop.clone())
    };
}

#[derive(Clone)]
enum FFState {
    Execution,
    ErrorCommandGenerate,
    ErrorCommandLaunch,
    ErrorCommandStatus(std::process::ExitStatus),
    Success,
}

#[derive(EnumIter, PartialEq, Clone)]
enum OutputFormat {
    Custom(String),
    MP4,
    MKV,
}

impl OutputFormat {
    fn to_str(&self) -> &str {
        match self {
            OutputFormat::Custom(_) => &"custom",
            OutputFormat::MP4 => &"mp4",
            OutputFormat::MKV => &"mkv",
        }
    }
    // like to_str() but returns inner content if custom
    fn inner(&self) -> &str {
        match self {
            OutputFormat::Custom(s) => &s,
            other => other.to_str(),
        }
    }
}

impl Default for OutputFormat {
    fn default() -> Self {
        Self::MKV
    }
}

#[derive(PartialEq)]
enum FFCmdType {
    Generated,
    Advanced,
    Manual,
}

impl FFCmdType {
    fn to_text_str(&self) -> &str {
        match self {
            FFCmdType::Generated => &"Basic",
            FFCmdType::Advanced => &"Advanced",
            FFCmdType::Manual => &"Manual",
        }
    }
}

struct FFCmd {
    input_file: Option<PathBuf>,
    output_file: Option<PathBuf>,
    format: Option<OutputFormat>,

    ffmpeg_path: Option<PathBuf>,
    cmd_type: FFCmdType,
    state: Option<FFState>,
}

impl FFCmd {
    fn get_cmd(&self) -> Option<Command> {
        if self.input_file.is_some() && self.output_file.is_some() {
            let path = self.get_ffmpeg_path_str().unwrap_or("ffmpeg");
            let mut cmd = Command::new(path);
            cmd.arg("-v")
                .arg("info")
                .arg("-i")
                .arg(self.input_name().unwrap())
                .arg(self.output_name().unwrap())
            ;
            Some(cmd)
        } else {
            None
        }
    }
    fn gen_cmd_text(&self) -> String {
        format!("{} -i {} {}",
            self.get_ffmpeg_path_str().unwrap_or("[ffmpeg]"),
            self.input_name().unwrap_or("[none]"),
            self.output_name().unwrap_or("[none]")
        )
    }
    fn gen_cmd_text_more(&self) -> Vec<String> {
        vec![
            self.get_ffmpeg_path_str().unwrap_or("[ffmpeg]").to_string(),
            "-i".to_string(),
            self.input_name().unwrap_or("[none]").to_string(),
            self.output_name().unwrap_or("[none]").to_string()
        ]
    }
    fn input_name(&self) -> Option<&str> {
        match &self.input_file {
            Some(p) => Some(p.to_str().unwrap_or("InvaildInputFileName")),
            None => None,
        }
    }
    fn output_name(&self) -> Option<&str> {
        match &self.output_file {
            Some(p) => Some(p.to_str().unwrap_or("InvaildOutputFileName")),
            None => None,
        }
    }
    fn get_format(&self) -> Option<OutputFormat> {
        self.format.clone()
    }
    /* NOTE: needed ?
    fn set_format(&self, format: OutputFormat) {
        self.format = format;
        if let Some(p) = self.output_file {
            self.output_file.set_extention(format.to_str());
        }
    }
    */
    fn set_self_format(&mut self) {
        if self.format.is_some() && self.output_file.is_some() {
            //let e = self.format.as_ref().unwrap().to_str();
            /*let e = match self.format.as_ref() {
                Some(OutputFormat::Custom(s)) => s,
                o => o.unwrap().to_str(),
            };*/
            let e = self.format.as_ref().unwrap().inner();
            let mut p = self.output_file.take().unwrap();
            p.set_extension(e);
            self.output_file.replace(p);
        }
    }

    fn get_ffmpeg_path_str(&self) -> Option<&str> {
        match &self.ffmpeg_path {
            Some(p) => Some(p.to_str().unwrap_or("InvaildFFmpegPath")),
            None => None,
        }
    }
    fn set_ffmpeg_path(&mut self, value: Option<PathBuf>) {
        self.ffmpeg_path = value;
    }
    fn set_cmd_type(&mut self, cmd_type: FFCmdType) {
        self.cmd_type = cmd_type;
    }
    fn get_state(&self) -> Option<FFState> {
        self.state.clone()
    }
    fn set_state(&mut self, state: Option<FFState>) {
        self.state = state;
    }
}

impl Default for FFCmd {
    fn default() -> Self {
        Self {
            input_file: None,
            output_file: None,
            format: None,

            ffmpeg_path: None,
            cmd_type: FFCmdType::Generated,
            state: None,
        }
    }
}

struct Config {
    font_prop: egui::FontId,
    font_small_prop: egui::FontId,
    font_mono: egui::FontId,
    config_window: bool,
    command_view_more: bool,
}

impl Config {
    fn is_config_window(&self) -> bool {
        self.config_window.clone()
    }
    fn set_config_window(&mut self, value: bool) {
        self.config_window = value;
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            font_prop: egui::FontId::proportional(22.0),
            font_small_prop: egui::FontId::proportional(11.0),
            font_mono: egui::FontId::monospace(22.0),
            config_window: false,
            command_view_more: false,
        }
    }
}

struct RSmpeg {
    ffcmd: FFCmd,
    config: Config,
    job: Option<std::process::Child>,
    job_stdout: Option<String>,
    job_stderr: Option<String>,

    first: bool, // first execution/frame, used to set dark mode because App::setup() mysteriously disapeared !!!!!
}

impl Default for RSmpeg {
    fn default() -> Self {
        Self {
            ffcmd: FFCmd::default(),
            config: Config::default(),
            job: None,
            job_stdout: None,
            job_stderr: None,

            first: true,
        }
    }
}

impl RSmpeg {
    fn new(_cc: &eframe::CreationContext<'_>) -> Self {
        Self::default()
    }
    /* HINT TODO:
     *   nothing inside stdout => ffmpeg or rust code's fault ?

    fn stds_collapsed(&mut self, ui: &mut egui::Ui) {
        ui.collapsing(mono_text!("sdtout", self), |ui| {
            if self.job_stdout.is_none() {
                let mut line = String::new();
                if let Some(stdout) = self.job.as_mut().unwrap().stdout.as_mut() {
                    let mut child_out = std::io::BufReader::new(stdout);
                    child_out.read_line(&mut line);
                } else {
                    line = "[no stdout]".to_string();
                }
                self.job_stdout = Some(line);
                //self.job_stdout = Some(format!("{:?}", Command::new("echo").arg("hello world!").output()));
            }

            egui::ScrollArea::vertical().show(ui, |ui| {
                ui.with_layout(egui::Layout::top_down(egui::Align::LEFT).with_cross_justify(true), |ui| {
                    ui.label(mono_text!(self.job_stdout.as_ref().unwrap(), self).weak());
                });
            });
        });

        ui.collapsing(mono_text!("sdterr", self), |ui| {
            if self.job_stderr.is_none() {
                let mut line = String::new();
                if let Some(stderr) = self.job.as_mut().unwrap().stderr.as_mut() {
                    let mut child_err = std::io::BufReader::new(stderr);
                    child_err.read_line(&mut line);
                } else {
                    line = "[no stderr]".to_string();
                }
                self.job_stderr = Some(line);
            }

            egui::ScrollArea::vertical().show(ui, |ui| {
                ui.with_layout(egui::Layout::top_down(egui::Align::LEFT).with_cross_justify(true), |ui| {
                    ui.label(mono_text!(self.job_stderr.as_ref().unwrap(), self).weak());
                });
            });
        });
    }
    */
}

impl eframe::App for RSmpeg {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {

        // first execution/frame, used to set dark mode because App::setup() mysteriously disapeared !!!!!
        if self.first {
            self.first = false;
            ctx.set_visuals(egui::style::Visuals::dark());
        }

        egui::CentralPanel::default().show(ctx, |ui| {
            egui::Grid::new("mainw_files").num_columns(2).show(ui, |ui| {
                ui.label(prop_text!("Input:", self));
                ui.with_layout(egui::Layout::right_to_left(), |ui| {
                    if ui.button(prop_text!("None", self)).clicked() {
                        self.ffcmd.input_file = None;
                    }
                    if ui.button(prop_text!("Choose", self)).clicked() {
                        let name = match self.ffcmd.input_name() {
                            Some(n) => String::from(n),
                            None => format!("input.{}", self.ffcmd.get_format().unwrap_or(OutputFormat::default()).to_str()),
                        };
                        if let Some(p) = FileDialog::new()
                                .set_title("Choose an input file")
                                //.set_directory(self.ffcmd.input_file.unwrap_or(PathBuf::new()).parent())
                                .set_file_name(&name)
                                .pick_file() {
                            self.ffcmd.input_file = Some(p);
                        }
                    }
                    ui.add(egui::TextEdit::singleline(&mut self.ffcmd.input_name().unwrap_or("Choose an input file"))
                        .font(self.config.font_prop.clone())
                        .desired_width(f32::INFINITY)
                    );
                });
                ui.end_row();

                ui.label(prop_text!("Output:", self));
                ui.with_layout(egui::Layout::right_to_left(), |ui| {
                    if ui.button(prop_text!("None", self)).clicked() {
                        self.ffcmd.output_file = None;
                    }
                    if ui.button(prop_text!("Choose", self)).clicked() {
                        let name = match self.ffcmd.output_name() {
                            Some(n) => String::from(n),
                            None => format!("output.{}", self.ffcmd.get_format().unwrap_or(OutputFormat::default()).inner()),
                        };
                        if let Some(p) = FileDialog::new()
                                .set_title("Choose an output file")
                                //.set_directory(self.ffcmd.output_file.unwrap_or(PathBuf::new()).parent())
                                .set_file_name(&name)
                                .save_file() {
                            self.ffcmd.output_file = Some(p);
                        }
                    }
                    ui.add(egui::TextEdit::singleline(&mut self.ffcmd.output_name().unwrap_or("Choose an output file"))
                        .font(self.config.font_prop.clone())
                        .desired_width(f32::INFINITY)
                    );
                });
                ui.end_row();
            });

            ui.separator();

            egui::Grid::new("mainw_ffmpeg_path").num_columns(1).show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(prop_text!("Path to", self));
                    ui.code(mono_text!("ffmpeg", self));
                    ui.label(prop_text!("executable:", self));
                });

                ui.end_row();

                ui.with_layout(egui::Layout::right_to_left(), |ui| {
                    if ui.button(prop_text!("None", self)).clicked() {
                        self.ffcmd.set_ffmpeg_path(None);
                    }
                    if ui.button(prop_text!("Select", self)).clicked() {
                        let name = match self.ffcmd.get_ffmpeg_path_str() {
                            Some(p) => String::from(p),
                            None => String::from("ffmpeg.exe"),
                        };
                        if let Some(p) = FileDialog::new()
                                .set_title("Select ffmpeg executable")
                                //.set_directory(self.ffcmd.output_file.unwrap_or(PathBuf::new()).parent())
                                .set_file_name(&name)
                                .pick_file() {
                            self.ffcmd.ffmpeg_path = Some(p);
                        }
                    }

                    ui.add(egui::TextEdit::singleline(&mut self.ffcmd.get_ffmpeg_path_str().unwrap_or("Select ffmpeg executable"))
                        .font(self.config.font_prop.clone())
                        .desired_width(f32::INFINITY)
                    );
                });
            });

            ui.separator();

            if self.ffcmd.cmd_type == FFCmdType::Generated {
                ui.horizontal_top(|ui| {
                    ui.label(prop_text!("Format:", self));
                    let current = match self.ffcmd.get_format() {
                        Some(f) => String::from(f.to_str()),
                        None => String::from("Choose"),
                    };
                    egui::ComboBox::from_id_source("mainw_format_gen_menu")
                        .selected_text(prop_text!(format!("{}", current), self))
                        .show_ui(ui, |ui| {
                            for variant in OutputFormat::iter() {
                                //TODO: make a format buffer for this menu
                                ui.selectable_value(&mut self.ffcmd.format, Some(variant.clone()), prop_text!(variant.to_str(), self));
                            }
                        });

                    ui.with_layout(egui::Layout::from_main_dir_and_cross_align(egui::Direction::RightToLeft, egui::Align::TOP), |ui| {
                        if ui.button(prop_text!("Advanced", self)).clicked() {
                            self.ffcmd.set_cmd_type(FFCmdType::Advanced);
                        }

                        if let Some(OutputFormat::Custom(mut custom)) = self.ffcmd.get_format() {
                            //let mut tmp = if custom.is_empty() { String::from("extension") } else { custom };
                            ui.add(egui::TextEdit::singleline(&mut custom)
                                .font(self.config.font_prop.clone())
                                .desired_width(f32::INFINITY)
                            );
                            self.ffcmd.format = Some(OutputFormat::Custom(custom));
                        }
                    });

                    self.ffcmd.set_self_format();
                });

                ui.separator();

                egui::ScrollArea::vertical().show(ui, |ui| {
                    if self.config.command_view_more {
                        egui::ScrollArea::horizontal().show(ui, |ui| {
                            for i in self.ffcmd.gen_cmd_text_more() {
                                ui.add(egui::TextEdit::singleline(&mut i.as_str())
                                    .font(self.config.font_mono.clone())
                                    .desired_width(f32::INFINITY)
                                );
                            }
                        });
                    } else {
                        ui.add(egui::TextEdit::multiline(&mut self.ffcmd.gen_cmd_text().as_str())
                            .font(self.config.font_mono.clone())
                            .desired_width(f32::INFINITY)
                        );
                    }
                });
            } else {
                ui.horizontal_top(|ui| {
                    ui.label(prop_text!(format!("{}: not implemented yet.", self.ffcmd.cmd_type.to_text_str()), self));

                    ui.with_layout(egui::Layout::from_main_dir_and_cross_align(egui::Direction::RightToLeft, egui::Align::TOP), |ui| {
                        if ui.button(prop_text!(FFCmdType::Manual.to_text_str(), self)).clicked() {
                            self.ffcmd.set_cmd_type(FFCmdType::Manual);
                        }
                        if ui.button(prop_text!(FFCmdType::Advanced.to_text_str(), self)).clicked() {
                            self.ffcmd.set_cmd_type(FFCmdType::Advanced);
                        }
                        if ui.button(prop_text!(FFCmdType::Generated.to_text_str(), self)).clicked() {
                            self.ffcmd.set_cmd_type(FFCmdType::Generated);
                        }
                    });
                });
            }

            /*
            { // NOTE: TEMPORARY TEST
                let alternatives = ["a", "b", "c", "d"];
                let mut selected = 2;
                egui::ComboBox::from_label("Select one!").show_index(
                    ui,
                    &mut selected,
                    alternatives.len(),
                    |i| alternatives[i].to_owned()
                );
            }
            */

            ui.with_layout(egui::Layout::from_main_dir_and_cross_align(egui::Direction::RightToLeft, egui::Align::BOTTOM), |ui| {
                if ui.button(prop_text!("Run", self)).clicked() {
                    if self.job.is_none() {
                        if let Some(mut cmd) = self.ffcmd.get_cmd() {
                            if let Ok(child) = cmd.spawn() {
                                self.job = Some(child);
                                self.ffcmd.set_state(Some(FFState::Execution));
                            } else {
                                self.ffcmd.set_state(Some(FFState::ErrorCommandLaunch));
                            }
                        } else {
                            // TODO/ERR: get_cmd() error management
                            self.ffcmd.set_state(Some(FFState::ErrorCommandGenerate));
                        }
                    }
                }
                if ui.button(prop_text!("Config", self)).clicked() {
                    self.config.set_config_window(true);
                }

                if self.config.command_view_more {
                    if ui.button(prop_text!("Less info", self)).clicked() {
                        self.config.command_view_more = false;
                    }
                } else {
                    if ui.button(prop_text!("More info", self)).clicked() {
                        self.config.command_view_more = true;
                    }
                }
            });
            //ui.with_layout(egui::Layout::from_main_dir_and_cross_align(egui::Direction::LeftToRight, egui::Align::BOTTOM), |ui| {
            //});

            if self.config.is_config_window() {
                egui::Window::new("Configuration")
                    .min_width(400.0)
                    .min_height(250.0)
                    .default_size(egui::Vec2::new(400.0,250.0))
                    .show(ctx, |ui| {
                        ui.horizontal(|ui| {
                            ui.label(prop_text!("Path to", self));
                            ui.code(mono_text!("ffmpeg", self));
                            ui.label(prop_text!("executable:", self));
                        });

                        ui.horizontal(|ui| {
                            ui.with_layout(egui::Layout::right_to_left(), |ui| {
                                if ui.button(prop_text!("None", self)).clicked() {
                                    self.ffcmd.set_ffmpeg_path(None);
                                }
                                if ui.button(prop_text!("Select", self)).clicked() {
                                    let name = match self.ffcmd.get_ffmpeg_path_str() {
                                        Some(p) => String::from(p),
                                        None => String::from("ffmpeg.exe"),
                                    };
                                    if let Some(p) = FileDialog::new()
                                            .set_title("Select ffmpeg executable")
                                            //.set_directory(self.ffcmd.output_file.unwrap_or(PathBuf::new()).parent())
                                            .set_file_name(&name)
                                            .pick_file() {
                                        self.ffcmd.ffmpeg_path = Some(p);
                                    }
                                }

                                ui.add(egui::TextEdit::singleline(&mut self.ffcmd.get_ffmpeg_path_str().unwrap_or("Select ffmpeg executable"))
                                    .font(self.config.font_prop.clone())
                                    .desired_width(f32::INFINITY)
                                );
                            });
                        });

                        ui.separator();

                        ui.horizontal(|ui| {
                            ui.label(prop_text!("Theme:", self));
                            egui::widgets::global_dark_light_mode_buttons(ui);
                        });

                        ui.with_layout(egui::Layout::bottom_up(egui::Align::Center), |ui| {
                            if ui.button(prop_text!("Close", self)).clicked() {
                                self.config.set_config_window(false);
                            }
                            ui.label(small_prop_text!(format!("state {} {:?}", STATE, ATTR), self));
                            ui.label(small_prop_text!(format!("rsmpeg v{} - written by lapingenieur", VERSION), self));
                        });
                    });
            }

            if let Some(state) = self.ffcmd.get_state() {
                match state {
                    FFState::Execution => egui::Window::new("Execution...")
                        .fixed_size(egui::Vec2::new(345.0,180.0))
                        .show(ctx, |ui| {
                            ui.horizontal_centered(|ui| {
                                ui.label(prop_text!("Executing", self));
                                ui.code(mono_text!("ffmpeg", self));
                                ui.label(prop_text!("command...", self));
                            });

                            if let Ok(Some(status)) = self.job.as_mut().unwrap().try_wait() {
                                if status.success() {
                                    self.ffcmd.set_state(Some(FFState::Success));
                                } else {
                                    self.ffcmd.set_state(Some(FFState::ErrorCommandStatus(status)));
                                }
                            }
                        }),
                    FFState::ErrorCommandLaunch => egui::Window::new("Error")
                        .fixed_size(egui::Vec2::new(345.0,180.0))
                        .show(ctx, |ui| {
                            ui.horizontal_centered(|ui| {
                                ui.vertical(|ui| {
                                    ui.label(prop_text!("Error: could not launch ffmpeg.", self));
                                    ui.horizontal(|ui| {
                                        ui.label(prop_text!("Help: is ", self));
                                        ui.code(mono_text!("ffmpeg", self));
                                        ui.label(prop_text!("installed and accessible?", self));
                                    });
                                });
                            });

                            ui.with_layout(egui::Layout::bottom_up(egui::Align::Center), |ui| {
                                if ui.button(prop_text!("Close", self)).clicked() {
                                    self.ffcmd.set_state(None);
                                    self.job = None;
                                }
                            });
                        }),
                    FFState::ErrorCommandGenerate => egui::Window::new("Error")
                        .fixed_size(egui::Vec2::new(345.0,180.0))
                        .show(ctx, |ui| {
                            ui.horizontal_centered(|ui| {
                                ui.vertical(|ui| {
                                    ui.horizontal(|ui| {
                                        ui.label(prop_text!("Error: could not generate ffmpeg", self));
                                        ui.code(mono_text!("ffmpeg", self));
                                        ui.label(prop_text!("command.", self));
                                    });
                                    ui.label(prop_text!("Help: did you set every needed parameter?", self));
                                });
                            });

                            ui.with_layout(egui::Layout::bottom_up(egui::Align::Center), |ui| {
                                if ui.button(prop_text!("Close", self)).clicked() {
                                    self.ffcmd.set_state(None);
                                    self.job = None;
                                }
                            });
                        }),
                    FFState::ErrorCommandStatus(status) => egui::Window::new("Error")
                        .fixed_size(egui::Vec2::new(345.0,180.0))
                        .show(ctx, |ui| {
                            ui.horizontal_centered(|ui| {
                                ui.label(prop_text!("Error:", self));
                                ui.code(mono_text!("ffmpeg", self));
                                ui.label(prop_text!("exited with status", self));
                                let tmp = match status.code() {
                                    Some(i) => i.to_string(),
                                    None => String::from("[non-zero]"),
                                };
                                ui.code(mono_text!(tmp, self));
                            });

                            // if uncommented, change fixed size to min size
                            //ui.separator();
                            //self.stds_collapsed(ui);

                            ui.with_layout(egui::Layout::bottom_up(egui::Align::Center), |ui| {
                                if ui.button(prop_text!("Close", self)).clicked() {
                                    self.ffcmd.set_state(None);
                                    self.job = None;
                                    self.job_stdout = None;
                                    self.job_stderr = None;
                                }
                            });
                        }),
                    FFState::Success => egui::Window::new("Success")
                        .min_width(345.0)
                        .min_height(180.0)
                        .show(ctx, |ui| {
                            ui.vertical_centered(|ui| {
                                ui.label(prop_text!("Execution went fine!", self));
                            });

                            //ui.separator();
                            //self.stds_collapsed(ui);

                            /*
                            ui.collapsing(mono_text!("sdtout", self), |ui| {
                                if self.job_stdout.is_none() {
                                    let mut line = String::new();
                                    if let Some(stdout) = self.job.as_mut().unwrap().stdout.as_mut() {
                                        let mut child_out = std::io::BufReader::new(stdout);
                                        child_out.read_line(&mut line);
                                    } else {
                                        line = "[no stdout]".to_string();
                                    }
                                    self.job_stdout = Some(line);
                                }

                                egui::ScrollArea::vertical().show(ui, |ui| {
                                    ui.with_layout(egui::Layout::top_down(egui::Align::LEFT).with_cross_justify(true), |ui| {
                                        ui.label(mono_text!(self.job_stdout.as_ref().unwrap(), self).weak());
                                    });
                                    /*
                                    ui.add(egui::TextEdit::singleline(&mut self.job_stdout.as_ref().unwrap().to_str())
                                        .font(self.config.font_mono.clone())
                                        .desired_width(f32::INFINITY)
                                        .desired_height(f32::INFINITY)
                                    );*/
                                });
                            });

                            ui.collapsing(mono_text!("sdterr", self), |ui| {
                                if self.job_stderr.is_none() {
                                    let mut line = String::new();
                                    if let Some(stderr) = self.job.as_mut().unwrap().stderr.as_mut() {
                                        let mut child_err = std::io::BufReader::new(stderr);
                                        child_err.read_line(&mut line);
                                    } else {
                                        line = "[no stderr]".to_string();
                                    }
                                    self.job_stderr = Some(line);
                                }

                                egui::ScrollArea::vertical().show(ui, |ui| {
                                    ui.with_layout(egui::Layout::top_down(egui::Align::LEFT).with_cross_justify(true), |ui| {
                                        ui.label(mono_text!(self.job_stderr.as_ref().unwrap(), self).weak());
                                    });
                                    /*
                                    ui.add(egui::TextEdit::singleline(&mut self.job_stderr.as_ref().unwrap().to_str())
                                        .font(self.config.font_mono.clone())
                                        .desired_width(f32::INFINITY)
                                        .desired_height(f32::INFINITY)
                                    );*/
                                });
                            });*/

                            ui.with_layout(egui::Layout::bottom_up(egui::Align::Center), |ui| {
                                if ui.button(prop_text!("Close", self)).clicked() {
                                    self.ffcmd.set_state(None);
                                    self.job = None;
                                    self.job_stdout = None;
                                    self.job_stderr = None;
                                }
                            });
                        }),
                };
            }
        });
    }
}

/*
fn search_config_file() -> Option<Path> {
    #[cfg(target_os = "windows")]
    {
        if let Some(appdata) = std::env::var_os("APPDATA") {
            let mut path = PathBuf::from(appdata);
            path.push("rsmpeg");
            path.push("ffmpeg.raw_path");
            match std::fs::File::open(path) {
                Some(file) => {
                    let ffmpeg = PathBuf::from(std::fs::read_to_string(path));
                    return Some(ffmpeg);
                },
                None => return None,
            };
        } else {
            return None;
        }
    }
    None
}
*/

fn main() {
    let opts = eframe::NativeOptions {
        min_window_size: Some(egui::Vec2::new(460.0, 250.0)),
        ..eframe::NativeOptions::default()
    };
    eframe::run_native("RSmpeg", opts, Box::new(|cc| Box::new(RSmpeg::new(cc))));
}
