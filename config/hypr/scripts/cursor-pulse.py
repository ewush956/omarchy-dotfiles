import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib, cairo
import gtk4_layer_shell
import subprocess
import json
import math


class Pulse(Gtk.Window):
    def __init__(self):
        super().__init__()

        gtk4_layer_shell.init_for_window(self)
        gtk4_layer_shell.set_layer(self, gtk4_layer_shell.Layer.OVERLAY)

        self.set_decorated(False)
        self.set_default_size(400, 400)

        output = subprocess.check_output(["hyprctl", "-j", "cursorpos"])
        pos = json.loads(output)

        self.x = pos["x"]
        self.y = pos["y"]

        self.radius = 20
        self.opacity = 1.0

        area = Gtk.DrawingArea()
        area.set_draw_func(self.draw)
        self.set_child(area)

        self.present()

        GLib.timeout_add(16, self.animate)

    def draw(self, area, cr, width, height):
        cr.set_source_rgba(1.0, 1.0, 0.0, self.opacity)
        cr.set_line_width(6)
        cr.arc(width / 2, height / 2, self.radius, 0, math.pi * 2)
        cr.stroke()

    def animate(self):
        self.radius += 6
        self.opacity -= 0.03

        self.queue_draw()

        if self.opacity <= 0:
            self.close()
            return False

        return True


app = Gtk.Application()


def activate(app):
    win = Pulse()
    win.set_application(app)


app.connect("activate", activate)
app.run()
