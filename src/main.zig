const r4os = @import("r4os");
const AppApi = struct {
    sys: r4os.r4sys.Context,
    desk: r4os.r4desk.Context,
    draw: r4os.r4draw.Context,
    net: r4os.r4net.Context,
    audio: r4os.r4audio.Context,
    dev: r4os.r4dev.Context,
    window: *r4os.Window,

    fn init(app: *r4os.App, window: *r4os.Window) ?AppApi {
        return .{
            .sys = app.system(),
            .desk = app.desktop() orelse return null,
            .draw = app.drawing() orelse return null,
            .net = app.networkLowLevel() orelse return null,
            .audio = app.audioLowLevel() orelse return null,
            .dev = app.devicesLowLevel() orelse return null,
            .window = window,
        };
    }
};
const std = @import("std");

const black = r4os.gui.default_palette.text;
const app_bg = r4os.gui.default_palette.face;
const panel_bg = r4os.gui.default_palette.client_bg;

const list_item_count: usize = 9;
const dropdown_item_count: usize = 3;
const file_item_count: usize = 3;
const menu_item_count: usize = 3;

const TextStore = struct {
    buffers: [48][96]u8 = undefined,
    next: usize = 0,

    fn add(self: *TextStore, text: []const u8) []const u8 {
        if (self.next >= self.buffers.len) {
            const fallback = self.buffers[self.buffers.len - 1][0..];
            fallback[0] = 0;
            return fallback[0..0];
        }
        const index = self.next;
        self.next += 1;
        const buffer = self.buffers[index][0..];
        @memset(buffer, 0);
        const len = @min(text.len, buffer.len - 1);
        if (len > 0) @memcpy(buffer[0..len], text[0..len]);
        buffer[len] = 0;
        return buffer[0..len];
    }
};

const FocusTarget = enum(usize) {
    menu_button,
    input,
    click_button,
    checkbox,
    radio_auto,
    radio_manual,
    dropdown,
    list,
};

const focus_items = [_]r4os.gui.FocusItem{
    .{},
    .{},
    .{},
    .{},
    .{},
    .{},
    .{},
    .{},
};

const capture_dialog_yes: usize = 100;
const capture_dialog_no: usize = 101;
const capture_dialog_ok: usize = 102;
const capture_dialog_cancel: usize = 103;

pub fn r4_app_main(contract: *r4os.App) i32 {
    var timers: [1]r4os.Timer = .{.{}};
    var window = contract.window(timers[0..]) orelse return r4os.abi.err_no_group;
    var ctx = AppApi.init(contract, &window) orelse return r4os.abi.err_no_group;
    var app = App{ .ctx = &ctx };
    return app.run();
}

const App = struct {
    ctx: *AppApi,
    w: i32 = 320,
    h: i32 = 180,
    clicks: u32 = 0,
    mouse_capture: r4os.gui.MouseCapture = .{},
    focus: r4os.gui.FocusState = .{ .index = focusIndex(.input) },
    input_initialized: bool = false,
    selected_index: usize = 0,
    selected_menu: usize = 0,
    menu_open: bool = false,
    checkbox_checked: bool = true,
    radio_selected: usize = 0,
    dropdown_open: bool = false,
    dropdown_selected: usize = 0,
    dialog_open: bool = false,
    file_dialog_open: bool = false,
    selected_file: usize = 0,
    input: r4os.gui.TextField(32) = .{},

    fn run(self: *App) i32 {
        return self.runHosted();
    }

    fn runConsole(self: *App) i32 {
        self.ctx.sys.println("R4OS SDK Example");

        if (self.ctx.sys.argsRaw()[0] != 0) {
            self.ctx.sys.print("ARGS: ");
            self.ctx.sys.print(self.ctx.sys.argsRaw());
            self.ctx.sys.write("\r\n");
        } else {
            self.ctx.sys.println("ARGS: <none>");
        }

        if (self.ctx.sys.exists("C:\\AUTOEXEC.BAT")) {
            self.ctx.sys.println("C:\\AUTOEXEC.BAT exists");
        } else {
            self.ctx.sys.println("C:\\AUTOEXEC.BAT missing");
        }

        if (!self.runAllocatorSmoke()) {
            self.ctx.sys.println("SDK allocator: FAILED");
            return 1;
        }
        self.ctx.sys.println("SDK allocator: OK");

        const now = self.ctx.sys.timeState();
        self.ctx.sys.write("TIME: ");
        print2(self.ctx, now.day);
        self.ctx.sys.putc('-');
        print2(self.ctx, now.month);
        self.ctx.sys.putc('-');
        self.ctx.sys.printU64(now.year);
        self.ctx.sys.putc(' ');
        print2(self.ctx, now.hour);
        self.ctx.sys.putc(':');
        print2(self.ctx, now.minute);
        self.ctx.sys.putc(':');
        print2(self.ctx, now.second);
        self.ctx.sys.write(if (now.valid != 0) " RTC " else " RTC? ");
        self.ctx.sys.print(backendName(now.monotonic_backend));
        self.ctx.sys.write(" ticks=");
        self.ctx.sys.printU64(now.monotonic_ticks);
        self.ctx.sys.write(" hz=");
        self.ctx.sys.printU64(now.monotonic_hz);
        self.ctx.sys.write("\r\n");

        self.printApiOverview();

        return 0;
    }

    fn printApiOverview(self: *App) void {
        self.ctx.sys.write("R4SYS table v");
        self.ctx.sys.printU64(self.ctx.sys.tableAbiVersion());
        self.ctx.sys.write(" size=");
        self.ctx.sys.printU64(self.ctx.sys.tableSize());
        self.ctx.sys.write(if (self.ctx.sys.contractValid()) " compatible\r\n" else " incompatible\r\n");

        var layout: r4os.abi.KeyboardLayoutInfo = .{};
        self.ctx.sys.write("DESKTOP: keyboard=");
        if (self.ctx.desk.keyboardLayoutCurrent(&layout) == 0) {
            self.ctx.sys.write(zSlice(layout.display[0..]));
            self.ctx.sys.write(" layouts=");
            self.ctx.sys.printU64(layout.count);
        } else {
            self.ctx.sys.write("unavailable");
        }
        self.ctx.sys.write("\r\n");

        self.ctx.sys.write("R4DRAW: screen=");
        self.ctx.sys.printU64(self.ctx.draw.screenWidth());
        self.ctx.sys.putc('x');
        self.ctx.sys.printU64(self.ctx.draw.screenHeight());
        self.ctx.sys.write(" rev=");
        self.ctx.sys.printU64(self.ctx.draw.displayRevision());
        self.ctx.sys.write("\r\n");

        var net_cfg: r4os.abi.NetConfigSnapshot = .{};
        const net_result = self.ctx.net.netConfigGet(&net_cfg);
        self.ctx.sys.write("R4NET: config=");
        self.ctx.sys.printI32(net_result);
        self.ctx.sys.write(" adapters=");
        self.ctx.sys.printU64(net_cfg.adapter_count);
        self.ctx.sys.write("\r\n");

        self.ctx.sys.print("R4AUDIO: SID model=");
        self.ctx.sys.print(self.ctx.audio.sidModelName());
        self.ctx.sys.write("\r\n");

        var devices: r4os.abi.DeviceInventorySummary = .{};
        const dev_result = self.ctx.dev.deviceInventorySummary(&devices);
        self.ctx.sys.write("R4DEV: inventory=");
        self.ctx.sys.printI32(dev_result);
        self.ctx.sys.write(" devices=");
        self.ctx.sys.printU64(devices.total);
        self.ctx.sys.write(" with_driver=");
        self.ctx.sys.printU64(devices.with_driver);
        self.ctx.sys.write("\r\n");
    }

    fn runAllocatorSmoke(self: *App) bool {
        const allocator = self.ctx.sys.allocator();
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(allocator);
        text.appendSlice(allocator, "R4OS") catch return false;
        text.append(allocator, '-') catch return false;
        text.appendSlice(allocator, "VMV2") catch return false;
        if (!std.mem.eql(u8, text.items, "R4OS-VMV2")) return false;

        var values: std.ArrayList(u32) = .empty;
        defer values.deinit(allocator);
        var i: u32 = 0;
        while (i < 24) : (i += 1) values.append(allocator, i * 3 + 1) catch return false;
        return values.items.len == 24 and values.items[0] == 1 and values.items[23] == 70;
    }

    fn runHosted(self: *App) i32 {
        self.initHostedState();
        _ = self.ctx.window.setTitle("SDK GUI Example");
        _ = self.ctx.window.setMinimumSize(300, 280);
        if (self.ctx.window.info()) |info| self.updateMetrics(info);
        self.renderHosted();

        while (!self.ctx.sys.programShouldClose()) {
            switch (self.ctx.window.waitMessage(r4os.time_contract.timeoutForever())) {
                .message => |message| switch (message) {
                    .close => return 0,
                    .resize => {
                        if (self.ctx.window.info()) |info| self.updateMetrics(info);
                        self.renderHosted();
                    },
                    .mouse => |mouse| switch (mouse.action) {
                        .down => self.handleMouseDown(mouse.x, mouse.y),
                        .up => self.handleMouseUp(mouse.x, mouse.y),
                        .move => {},
                    },
                    .key => |key_message| {
                        const key = key_message.key;
                        if (self.handleModalKey(key)) {
                            continue;
                        }
                        if (self.handleFocusedKey(key)) {
                            self.renderHosted();
                            continue;
                        }
                        if (key == r4os.gui.Key.escape) return 0;
                        if (self.input.focused and self.handleInputKey(key)) self.renderHosted();
                    },
                    else => {},
                },
                .failure => |raw| return raw,
                .timed_out => {},
            }
        }

        return 0;
    }

    fn initHostedState(self: *App) void {
        if (self.input_initialized) return;
        self.input.set("R4OS");
        self.input.focused = true;
        _ = self.focus.set(focus_items[0..], focusIndex(.input));
        self.input_initialized = true;
    }

    fn updateMetrics(self: *App, info: r4os.abi.GuiWindowInfo) void {
        self.w = clampI32(info.client_w, 180, 1600);
        self.h = clampI32(info.client_h, 100, 1000);
    }

    fn renderHosted(self: *App) void {
        var paint = switch (self.ctx.window.beginPaint()) {
            .paint => |value| value,
            .failure => return,
        };
        defer paint.discard();
        const canvas = paint.canvas;
        var texts = TextStore{};
        var list_items = buildListItems(&texts);
        var dropdown_items = buildDropdownItems(&texts);
        var menu_items = buildMenuItems(&texts);
        var file_items = buildFileItems(&texts);
        var scratch: [64]u8 = .{0} ** 64;
        var count: [32]u8 = .{0} ** 32;
        self.syncInputFocus();

        _ = canvas.clear(app_bg);
        _ = canvas.label(.{
            .rect = .{ .x = 12, .y = 12, .w = @max(60, canvas.w - 96), .h = 16 },
            .text = texts.add("R4OS SDK GUI Example"),
            .fg = black,
            .bg = app_bg,
        }, scratch[0..]);
        _ = canvas.button(.{
            .rect = self.menuButtonRect(),
            .text = texts.add("Menu"),
            .state = if (self.mouse_capture.isActive(focusIndex(.menu_button)) or self.menu_open) .pressed else .normal,
            .focused = self.hasFocus(.menu_button),
        }, scratch[0..]);

        _ = canvas.rect(.{ .x = 12, .y = 36, .w = canvas.w - 24, .h = 36 }, panel_bg);
        _ = canvas.label(.{
            .rect = .{ .x = 20, .y = 44, .w = canvas.w - 40, .h = 16 },
            .text = texts.add("Controls use shared r4os.gui drawing, metrics and hit-tests."),
            .fg = black,
            .bg = panel_bg,
        }, scratch[0..]);

        _ = canvas.groupBox(.{
            .rect = self.controlsGroupRect(),
            .title = texts.add("Controls"),
        }, scratch[0..]);

        _ = canvas.label(.{
            .rect = .{ .x = 24, .y = 92, .w = 56, .h = 22 },
            .text = texts.add("Input:"),
            .fg = black,
            .bg = app_bg,
        }, scratch[0..]);
        _ = self.input.draw(canvas, self.inputRect(), scratch[0..]);

        _ = canvas.button(.{
            .rect = self.buttonRect(),
            .text = texts.add("Click"),
            .state = if (self.mouse_capture.isActive(focusIndex(.click_button))) .pressed else .normal,
            .focused = self.hasFocus(.click_button),
            .is_default = true,
        }, scratch[0..]);

        _ = canvas.label(.{
            .rect = .{ .x = 128, .y = 124, .w = canvas.w - 150, .h = 24 },
            .text = clickText(count[0..], self.clicks),
            .fg = black,
            .bg = app_bg,
        }, scratch[0..]);

        _ = canvas.checkbox(.{
            .rect = self.checkboxRect(),
            .text = texts.add("Use DHCP"),
            .checked = self.checkbox_checked,
            .focused = self.hasFocus(.checkbox),
        }, scratch[0..]);
        _ = canvas.radioButton(.{
            .rect = self.radioDhcpRect(),
            .text = texts.add("Automatic"),
            .selected = self.radio_selected == 0,
            .focused = self.hasFocus(.radio_auto),
        }, scratch[0..]);
        _ = canvas.radioButton(.{
            .rect = self.radioStaticRect(),
            .text = texts.add("Manual"),
            .selected = self.radio_selected == 1,
            .focused = self.hasFocus(.radio_manual),
        }, scratch[0..]);
        _ = canvas.dropdown(.{
            .rect = self.dropdownRect(),
            .items = dropdown_items[0..],
            .selected_index = self.dropdown_selected,
            .open = self.dropdown_open,
            .focused = self.hasFocus(.dropdown),
        }, scratch[0..]);
        _ = canvas.separator(.{
            .rect = self.separatorRect(),
        });
        _ = canvas.label(.{
            .rect = .{ .x = 12, .y = canvas.h - 24, .w = canvas.w - 24, .h = 16 },
            .text = texts.add(menuStatus(self.selected_menu)),
            .alignment = .center,
            .fg = black,
            .bg = app_bg,
        }, scratch[0..]);

        if (self.listRect().h >= 16) {
            _ = canvas.label(.{
                .rect = .{ .x = 24, .y = 202, .w = canvas.w - 48, .h = 16 },
                .text = texts.add("SDK controls:"),
                .fg = black,
                .bg = app_bg,
            }, scratch[0..]);
            _ = canvas.list(.{
                .rect = self.listRect(),
                .items = list_items[0..],
                .selected_index = self.selected_index,
                .disabled_index = 6,
                .focused = self.hasFocus(.list),
            }, scratch[0..]);
        }

        if (self.menu_open) {
            _ = canvas.menu(.{
                .rect = self.menuRect(),
                .items = menu_items[0..],
                .selected_index = self.selected_menu,
            }, scratch[0..]);
        }

        if (self.dropdown_open) {
            _ = canvas.dropdown(.{
                .rect = self.dropdownRect(),
                .items = dropdown_items[0..],
                .selected_index = self.dropdown_selected,
                .open = true,
                .focused = self.hasFocus(.dropdown),
            }, scratch[0..]);
        }

        if (self.dialog_open) {
            _ = canvas.messageDialog(self.messageDialog(&texts), scratch[0..]);
        }

        if (self.file_dialog_open) {
            _ = canvas.fileDialog(self.fileDialog(file_items[0..], &texts), scratch[0..]);
        }

        _ = paint.present();
    }

    fn handleMouseDown(self: *App, x: i32, y: i32) void {
        self.mouse_capture.clear();
        if (self.file_dialog_open) {
            var texts = TextStore{};
            var file_items = buildFileItems(&texts);
            const dialog = self.fileDialog(file_items[0..], &texts);
            switch (dialog.actionAt(x, y)) {
                .select => {
                    if (dialog.indexAt(x, y)) |index| self.selected_file = index;
                    self.renderHosted();
                },
                .ok => {
                    self.mouse_capture.begin(capture_dialog_ok, .submitted);
                    self.renderHosted();
                },
                .cancel => {
                    self.mouse_capture.begin(capture_dialog_cancel, .cancelled);
                    self.renderHosted();
                },
                else => {},
            }
            return;
        }

        if (self.dialog_open) {
            var texts = TextStore{};
            const dialog = self.messageDialog(&texts);
            switch (dialog.actionAt(x, y)) {
                .yes => {
                    self.mouse_capture.begin(capture_dialog_yes, .submitted);
                    self.renderHosted();
                },
                .no => {
                    self.mouse_capture.begin(capture_dialog_no, .cancelled);
                    self.renderHosted();
                },
                else => {},
            }
            return;
        }

        if (self.menu_open) {
            var texts = TextStore{};
            var menu_items = buildMenuItems(&texts);
            const menu = r4os.gui.Menu{ .rect = self.menuRect(), .items = menu_items[0..] };
            if (menu.indexAt(x, y)) |index| {
                self.selected_menu = index;
                self.menu_open = false;
                if (index == 0) self.file_dialog_open = true;
                self.renderHosted();
                return;
            }
        }

        if (self.dropdown_open) {
            var texts = TextStore{};
            var dropdown_items = buildDropdownItems(&texts);
            const dropdown_control = self.dropdown(dropdown_items[0..]);
            if (dropdown_control.indexAt(x, y)) |index| {
                _ = index;
                self.mouse_capture.begin(focusIndex(.dropdown), .selection_changed);
                _ = self.focus.set(focus_items[0..], focusIndex(.dropdown));
                self.renderHosted();
                return;
            }
            if (self.dropdownRect().contains(x, y)) {
                self.mouse_capture.begin(focusIndex(.dropdown), .clicked);
                _ = self.focus.set(focus_items[0..], focusIndex(.dropdown));
                self.renderHosted();
                return;
            }
            self.dropdown_open = false;
        }

        if (self.menuButtonRect().contains(x, y)) {
            self.mouse_capture.begin(focusIndex(.menu_button), .clicked);
            _ = self.focus.set(focus_items[0..], focusIndex(.menu_button));
            self.dropdown_open = false;
            self.renderHosted();
            return;
        }

        self.menu_open = false;
        if (self.dropdownRect().contains(x, y)) {
            self.mouse_capture.begin(focusIndex(.dropdown), .clicked);
            _ = self.focus.set(focus_items[0..], focusIndex(.dropdown));
            self.renderHosted();
            return;
        }
        if (self.checkboxRect().contains(x, y)) {
            self.mouse_capture.begin(focusIndex(.checkbox), .changed);
            _ = self.focus.set(focus_items[0..], focusIndex(.checkbox));
            self.renderHosted();
            return;
        }
        if (self.radioDhcpRect().contains(x, y)) {
            self.mouse_capture.begin(focusIndex(.radio_auto), .changed);
            _ = self.focus.set(focus_items[0..], focusIndex(.radio_auto));
            self.renderHosted();
            return;
        }
        if (self.radioStaticRect().contains(x, y)) {
            self.mouse_capture.begin(focusIndex(.radio_manual), .changed);
            _ = self.focus.set(focus_items[0..], focusIndex(.radio_manual));
            self.renderHosted();
            return;
        }
        if (self.inputRect().contains(x, y)) {
            _ = self.focus.set(focus_items[0..], focusIndex(.input));
            self.renderHosted();
            return;
        }
        var texts = TextStore{};
        var list_items = buildListItems(&texts);
        if ((r4os.gui.List{ .rect = self.listRect(), .items = list_items[0..], .disabled_index = 6 }).indexAt(x, y)) |index| {
            _ = index;
            self.mouse_capture.begin(focusIndex(.list), .selection_changed);
            _ = self.focus.set(focus_items[0..], focusIndex(.list));
            self.renderHosted();
            return;
        }
        if (self.buttonRect().contains(x, y)) {
            self.mouse_capture.begin(focusIndex(.click_button), .clicked);
            _ = self.focus.set(focus_items[0..], focusIndex(.click_button));
            self.renderHosted();
            return;
        }
        self.renderHosted();
    }

    fn handleMouseUp(self: *App, x: i32, y: i32) void {
        if (self.file_dialog_open) {
            var texts = TextStore{};
            var file_items = buildFileItems(&texts);
            const dialog = self.fileDialog(file_items[0..], &texts);
            if (self.mouse_capture.release(capture_dialog_ok, dialog.okRect().contains(x, y)) == .submitted or
                self.mouse_capture.release(capture_dialog_cancel, dialog.cancelRect().contains(x, y)) == .cancelled)
            {
                self.file_dialog_open = false;
                self.renderHosted();
            }
            return;
        }

        if (self.dialog_open) {
            var texts = TextStore{};
            const dialog = self.messageDialog(&texts);
            if (self.mouse_capture.release(capture_dialog_yes, dialog.yesRect().contains(x, y)) == .submitted) {
                self.selected_menu = 0;
                self.dialog_open = false;
                self.renderHosted();
                return;
            }
            if (self.mouse_capture.release(capture_dialog_no, dialog.noRect().contains(x, y)) == .cancelled) {
                self.selected_menu = 2;
                self.dialog_open = false;
                self.renderHosted();
            }
            return;
        }

        var texts_dropdown = TextStore{};
        var dropdown_items = buildDropdownItems(&texts_dropdown);
        const dropdown_control = self.dropdown(dropdown_items[0..]);
        switch (self.mouse_capture.release(focusIndex(.dropdown), dropdown_control.indexAt(x, y) != null or self.dropdownRect().contains(x, y))) {
            .selection_changed => {
                if (dropdown_control.indexAt(x, y)) |index| self.dropdown_selected = index;
                self.dropdown_open = false;
                self.renderHosted();
                return;
            },
            .clicked => {
                self.dropdown_open = !self.dropdown_open;
                self.menu_open = false;
                self.renderHosted();
                return;
            },
            else => {},
        }

        switch (self.mouse_capture.release(focusIndex(.menu_button), self.menuButtonRect().contains(x, y))) {
            .clicked => {
                self.menu_open = !self.menu_open;
                self.dropdown_open = false;
                self.renderHosted();
                return;
            },
            else => {},
        }

        switch (self.mouse_capture.release(focusIndex(.checkbox), self.checkboxRect().contains(x, y))) {
            .changed => {
                self.checkbox_checked = !self.checkbox_checked;
                self.renderHosted();
                return;
            },
            else => {},
        }

        switch (self.mouse_capture.release(focusIndex(.radio_auto), self.radioDhcpRect().contains(x, y))) {
            .changed => {
                self.radio_selected = 0;
                self.renderHosted();
                return;
            },
            else => {},
        }

        switch (self.mouse_capture.release(focusIndex(.radio_manual), self.radioStaticRect().contains(x, y))) {
            .changed => {
                self.radio_selected = 1;
                self.renderHosted();
                return;
            },
            else => {},
        }

        var texts_list = TextStore{};
        var list_items = buildListItems(&texts_list);
        switch (self.mouse_capture.release(focusIndex(.list), (r4os.gui.List{ .rect = self.listRect(), .items = list_items[0..], .disabled_index = 6 }).indexAt(x, y) != null)) {
            .selection_changed => {
                if ((r4os.gui.List{ .rect = self.listRect(), .items = list_items[0..], .disabled_index = 6 }).indexAt(x, y)) |index| self.selected_index = index;
                self.renderHosted();
                return;
            },
            else => {},
        }

        switch (self.mouse_capture.release(focusIndex(.click_button), self.buttonRect().contains(x, y))) {
            .clicked => {
                self.submitClick();
                self.renderHosted();
                return;
            },
            else => {},
        }
    }

    fn handleModalKey(self: *App, key: u8) bool {
        if (self.file_dialog_open) {
            var texts = TextStore{};
            var file_items = buildFileItems(&texts);
            const dialog = self.fileDialog(file_items[0..], &texts);
            const action = dialog.keyAction(key);
            switch (action) {
                .previous, .next => {
                    self.selected_file = dialog.selectedIndexForAction(action);
                    self.renderHosted();
                },
                .ok, .cancel => {
                    self.file_dialog_open = false;
                    self.renderHosted();
                },
                else => {},
            }
            return true;
        }

        if (self.dialog_open) {
            var texts = TextStore{};
            switch (self.messageDialog(&texts).keyAction(key)) {
                .yes => {
                    self.selected_menu = 0;
                    self.dialog_open = false;
                    self.renderHosted();
                },
                .no, .ok, .cancel => {
                    self.selected_menu = 2;
                    self.dialog_open = false;
                    self.renderHosted();
                },
                else => {},
            }
            return true;
        }

        return false;
    }

    fn handleFocusedKey(self: *App, key: u8) bool {
        if (self.menu_open) {
            var texts = TextStore{};
            var menu_items = buildMenuItems(&texts);
            const menu = r4os.gui.Menu{ .rect = self.menuRect(), .items = menu_items[0..], .selected_index = self.selected_menu };
            const result = menu.keyAction(key);
            switch (result.action) {
                .selection_changed => {
                    if (result.index) |index| self.selected_menu = index;
                    return true;
                },
                .submitted => {
                    if (result.index) |index| self.activateMenuItem(index);
                    return true;
                },
                .cancelled => {
                    self.menu_open = false;
                    return true;
                },
                else => {},
            }
        }

        if (self.dropdown_open) {
            var texts = TextStore{};
            var dropdown_items = buildDropdownItems(&texts);
            const result = self.dropdown(dropdown_items[0..]).keyAction(key);
            switch (result.action) {
                .selection_changed => {
                    self.dropdown_selected = result.index;
                    return true;
                },
                .submitted => {
                    self.dropdown_open = false;
                    return true;
                },
                .cancelled => {
                    self.dropdown_open = false;
                    return true;
                },
                else => {},
            }
        }

        if (self.hasFocus(.dropdown)) {
            var texts = TextStore{};
            var dropdown_items = buildDropdownItems(&texts);
            const result = self.dropdown(dropdown_items[0..]).keyAction(key);
            switch (result.action) {
                .selection_changed => {
                    self.dropdown_selected = result.index;
                    return true;
                },
                .submitted, .clicked => {
                    self.dropdown_open = !self.dropdown_open;
                    return true;
                },
                .cancelled => return false,
                else => {},
            }
        }

        if (self.hasFocus(.list)) {
            var texts = TextStore{};
            var list_items = buildListItems(&texts);
            const result = (r4os.gui.List{ .rect = self.listRect(), .items = list_items[0..], .selected_index = self.selected_index, .disabled_index = 6 }).keyAction(key);
            switch (result.action) {
                .selection_changed => {
                    self.selected_index = result.index;
                    return true;
                },
                .submitted => return true,
                else => {},
            }
        }

        if (self.hasFocus(.input) and key != r4os.gui.Key.tab and key != r4os.gui.Key.shift_tab and key != r4os.gui.Key.enter and key != r4os.gui.Key.escape) {
            return false;
        }

        const result = self.focus.handleKey(focus_items[0..], key);
        switch (result.action) {
            .changed => {
                self.syncInputFocus();
                return true;
            },
            .submitted, .clicked => return self.activateFocused(result.action),
            .cancelled => {
                if (self.dropdown_open or self.menu_open) {
                    self.dropdown_open = false;
                    self.menu_open = false;
                    return true;
                }
                return false;
            },
            else => return false,
        }
    }

    fn activateFocused(self: *App, action: r4os.gui.ControlAction) bool {
        _ = action;
        switch (focusedTarget(self.focus.index)) {
            .menu_button => {
                self.menu_open = !self.menu_open;
                self.dropdown_open = false;
                return true;
            },
            .input => {
                self.submitClick();
                return true;
            },
            .click_button => {
                self.submitClick();
                return true;
            },
            .checkbox => {
                self.checkbox_checked = !self.checkbox_checked;
                return true;
            },
            .radio_auto => {
                self.radio_selected = 0;
                return true;
            },
            .radio_manual => {
                self.radio_selected = 1;
                return true;
            },
            .dropdown => {
                self.dropdown_open = !self.dropdown_open;
                return true;
            },
            .list => return true,
        }
    }

    fn activateMenuItem(self: *App, index: usize) void {
        self.selected_menu = index;
        self.menu_open = false;
        if (index == 0) self.file_dialog_open = true;
    }

    fn submitClick(self: *App) void {
        self.clicks +%= 1;
        self.dialog_open = true;
    }

    fn handleInputKey(self: *App, key: u8) bool {
        switch (key) {
            r4os.gui.Key.ctrl_c => return self.input.copyToClipboard(&self.ctx.desk),
            r4os.gui.Key.ctrl_x => return self.input.cutToClipboard(&self.ctx.desk),
            r4os.gui.Key.ctrl_v => return self.input.pasteFromClipboard(&self.ctx.desk),
            r4os.gui.Key.left, r4os.gui.Key.right, r4os.gui.Key.home, r4os.gui.Key.end, r4os.gui.Key.delete => return self.input.handleKey(key),
            else => return self.input.handleKey(key),
        }
    }

    fn hasFocus(self: *const App, target: FocusTarget) bool {
        return self.focus.index == focusIndex(target);
    }

    fn syncInputFocus(self: *App) void {
        self.input.focused = self.hasFocus(.input);
    }

    fn buttonRect(self: *const App) r4os.gui.Rect {
        _ = self;
        return .{ .x = 24, .y = 122, .w = 96, .h = 26 };
    }

    fn inputRect(self: *const App) r4os.gui.Rect {
        return .{ .x = 84, .y = 88, .w = @max(88, self.w - 108), .h = 24 };
    }

    fn listRect(self: *const App) r4os.gui.Rect {
        return .{ .x = 24, .y = 220, .w = @max(120, self.w - 48), .h = @max(0, self.h - 250) };
    }

    fn controlsGroupRect(self: *const App) r4os.gui.Rect {
        return .{ .x = 12, .y = 78, .w = @max(180, self.w - 24), .h = 134 };
    }

    fn checkboxRect(self: *const App) r4os.gui.Rect {
        _ = self;
        return .{ .x = 24, .y = 154, .w = 120, .h = 20 };
    }

    fn radioDhcpRect(self: *const App) r4os.gui.Rect {
        return .{ .x = @max(150, @divTrunc(self.w, 2)), .y = 122, .w = 130, .h = 20 };
    }

    fn radioStaticRect(self: *const App) r4os.gui.Rect {
        return .{ .x = @max(150, @divTrunc(self.w, 2)), .y = 146, .w = 130, .h = 20 };
    }

    fn dropdownRect(self: *const App) r4os.gui.Rect {
        return .{ .x = @max(150, @divTrunc(self.w, 2)), .y = 176, .w = @max(120, @divTrunc(self.w, 2) - 24), .h = 22 };
    }

    fn dropdown(self: *const App, items: []const []const u8) r4os.gui.Dropdown {
        return .{
            .rect = self.dropdownRect(),
            .items = items,
            .selected_index = self.dropdown_selected,
            .open = self.dropdown_open,
        };
    }

    fn separatorRect(self: *const App) r4os.gui.Rect {
        return .{ .x = 24, .y = 184, .w = @max(100, @divTrunc(self.w, 2) - 40), .h = 8 };
    }

    fn menuButtonRect(self: *const App) r4os.gui.Rect {
        return .{ .x = @max(96, self.w - 76), .y = 8, .w = 64, .h = 24 };
    }

    fn menuRect(self: *const App) r4os.gui.Rect {
        return .{ .x = @max(54, self.w - 126), .y = 34, .w = 114, .h = 60 };
    }

    fn dialogRect(self: *const App) r4os.gui.Rect {
        return r4os.gui.centeredRect(.{ .x = 0, .y = 0, .w = self.w, .h = self.h }, @min(230, @max(160, self.w - 32)), 96);
    }

    fn fileDialogRect(self: *const App) r4os.gui.Rect {
        return r4os.gui.centeredRect(.{ .x = 0, .y = 0, .w = self.w, .h = self.h }, @min(260, @max(190, self.w - 24)), @min(170, @max(132, self.h - 18)));
    }

    fn messageDialog(self: *const App, texts: *TextStore) r4os.gui.MessageDialog {
        return .{
            .rect = self.dialogRect(),
            .title = texts.add("SDK Question"),
            .message = texts.add("Use the shared MessageBox?"),
            .kind = .question,
            .buttons = .yes_no,
        };
    }

    fn fileDialog(self: *const App, items: []const []const u8, texts: *TextStore) r4os.gui.FileDialog {
        return .{
            .rect = self.fileDialogRect(),
            .title = texts.add("Open File"),
            .path = texts.add("C:\\"),
            .items = items,
            .mode = .open,
            .file_name = texts.add(self.selectedFileName()),
            .ok_text = texts.add("Open"),
            .cancel_text = texts.add("Cancel"),
            .selected_index = self.selected_file,
        };
    }

    fn selectedFileName(self: *const App) []const u8 {
        if (self.selected_file >= file_item_count) return "";
        return fileItemText(self.selected_file);
    }
};

fn menuStatus(index: usize) []const u8 {
    if (index >= menu_item_count) return "Click Menu or the list to select SDK controls.";
    if (index == 0) return "Menu selected: Open";
    if (index == 2) return "Menu selected: Close";
    return "Click Menu or the list to select SDK controls.";
}

fn buildListItems(texts: *TextStore) [list_item_count][]const u8 {
    var items: [list_item_count][]const u8 = undefined;
    var i: usize = 0;
    while (i < items.len) : (i += 1) items[i] = texts.add(listItemText(i));
    return items;
}

fn listItemText(index: usize) []const u8 {
    return switch (index) {
        0 => "Label",
        1 => "Button",
        2 => "TextField",
        3 => "List",
        4 => "Checkbox",
        5 => "RadioButton",
        6 => "GroupBox",
        7 => "Separator",
        8 => "Dropdown",
        else => "",
    };
}

fn buildDropdownItems(texts: *TextStore) [dropdown_item_count][]const u8 {
    var items: [dropdown_item_count][]const u8 = undefined;
    var i: usize = 0;
    while (i < items.len) : (i += 1) items[i] = texts.add(dropdownItemText(i));
    return items;
}

fn dropdownItemText(index: usize) []const u8 {
    return switch (index) {
        0 => "DHCP",
        1 => "Static IPv4",
        2 => "Link-local",
        else => "",
    };
}

fn buildFileItems(texts: *TextStore) [file_item_count][]const u8 {
    var items: [file_item_count][]const u8 = undefined;
    var i: usize = 0;
    while (i < items.len) : (i += 1) items[i] = texts.add(fileItemText(i));
    return items;
}

fn fileItemText(index: usize) []const u8 {
    return switch (index) {
        0 => "AUTOEXEC.BAT",
        1 => "CONFIG.R4S",
        2 => "DESKTOP",
        else => "",
    };
}

fn buildMenuItems(texts: *TextStore) [menu_item_count]r4os.gui.MenuItem {
    var items: [menu_item_count]r4os.gui.MenuItem = undefined;
    items[0] = .{ .text = texts.add(menuItemText(0)) };
    items[1] = .{ .text = texts.add(menuItemText(1)), .enabled = false };
    items[2] = .{ .text = texts.add(menuItemText(2)), .separator_before = true };
    return items;
}

fn menuItemText(index: usize) []const u8 {
    return switch (index) {
        0 => "Open",
        1 => "Save",
        2 => "Close",
        else => "",
    };
}

fn clickText(buffer: []u8, clicks: u32) []const u8 {
    if (buffer.len == 0) return buffer[0..0];
    @memset(buffer, 0);
    const prefix = "Clicks: ";
    const prefix_len = min(prefix.len, buffer.len - 1);
    @memcpy(buffer[0..prefix_len], prefix[0..prefix_len]);
    if (prefix_len >= buffer.len - 1) return buffer[0..prefix_len];

    var digits: [10]u8 = .{0} ** 10;
    var count: usize = 0;
    var value = clicks;
    if (value == 0) {
        digits[0] = '0';
        count = 1;
    } else {
        while (value > 0 and count < digits.len) : (count += 1) {
            digits[count] = '0' + @as(u8, @intCast(value % 10));
            value /= 10;
        }
    }

    var out = prefix_len;
    while (count > 0 and out < buffer.len - 1) {
        count -= 1;
        buffer[out] = digits[count];
        out += 1;
    }
    buffer[out] = 0;
    return buffer[0..out];
}

fn min(a: usize, b: usize) usize {
    return if (a < b) a else b;
}

fn print2(ctx: *const AppApi, value: u8) void {
    if (value < 10) ctx.sys.putc('0');
    ctx.sys.printU64(value);
}

fn backendName(value: u32) [*:0]const u8 {
    return switch (value) {
        0 => "PIT",
        1 => "HPET",
        2 => "LAPIC",
        else => "UNKNOWN",
    };
}

fn zSlice(buffer: []const u8) []const u8 {
    var len: usize = 0;
    while (len < buffer.len and buffer[len] != 0) : (len += 1) {}
    return buffer[0..len];
}

fn clampI32(value: i32, min_value: i32, max_value: i32) i32 {
    if (value < min_value) return min_value;
    if (value > max_value) return max_value;
    return value;
}

fn focusIndex(target: FocusTarget) usize {
    return @intFromEnum(target);
}

fn focusedTarget(index: usize) FocusTarget {
    if (index >= focus_items.len) return .input;
    return @enumFromInt(index);
}
