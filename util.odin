#+build linux
package wayland

generic_c_call :: proc "c" ()
dispatcher_func_t :: proc "c" (impl: rawptr, target: rawptr, opcode: u32, msg: ^message,args: [^]argument)
event_queue :: struct {}
proxy :: struct{}
argument :: union {}
message :: struct {
   name: cstring,
   signature: cstring,
   types: [^]^interface
}
interface :: struct {
   name: cstring,
   version: i32,
   method_count: i32,
   methods: [^]message,
   event_count: i32,
   events: [^]message
}