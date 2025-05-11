# Wayland Bindings for Odin
Bindings for creating Wayland clients. Protocol bindings are grouped according to their prefixes (except for ones starting with 'z', which is supposed to mean that the protocol is unstable. For example: zxdg_decoration is put into xdg directory).

I also included bindings to libdecor which comes in handy, especially if you are developing for GNOME since it doesn't support server-side decorations.

Required libraries are:
- libwayland-client
- libdecor (for libdecor example)

## Resources
- https://wayland-book.com
- https://wayland.app
- https://wayland.freedesktop.org/docs/html/apb.html
