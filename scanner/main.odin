package wayland_scanner
import "core:fmt"
import "core:encoding/xml"
import "core:log"
import "core:strings"
import "core:flags"
import "core:os"
import "core:path/filepath"

Procedure_Type :: enum {
   Request,
   Event,
}
Procedure :: struct {
   name: string,
   description: string,
   type: Procedure_Type,
   args: []Argument, // This does not include ret
   ret: Maybe(Argument),
   new_id: Maybe(Argument),
   is_destructor: bool
}

Enum_Entry :: struct {
   name: string,
   value: string,
}

Enumeration :: struct {
   name: string,
   description: string,
   entries: []Enum_Entry
}

Interface :: struct {
   name: string,
   unstripped_name: string,
   description: string,
   requests: []Procedure,
   events: []Procedure,
   enums: []Enumeration,

}

Protocol :: struct {
   name: string,
   interfaces: []Interface
}

Argument_Type :: enum {
   New_Id,
   Int,
   Unsigned,
   Fixed,
   String,
   Object,
   Array,
   Fd,
   Enum,
}
Argument :: struct {
   name: string,
   type: Argument_Type,

   nullable: bool,

   interface_name: string,
   enum_name: string // If type is enum

   // TODO: summary
}
get_description :: proc(doc: ^xml.Document, id: u32) -> string {
   desc_id,found := find_child(doc, id, "description")
   if !found {
      return ""
   }
   values := doc.elements[desc_id].value
   if len(values) == 0 {
      return ""
   }
   return values[0].(string)
}
get_name :: proc(doc: ^xml.Document, id: u32) -> string {
   name, found := find_attr(doc,id,"name"); assert(found)
   return name
}

iterate_child :: proc(doc: ^xml.Document, parent_id: u32, ident: string) -> (id: u32, ok: bool) {
   @(static) index_map :map[u32]int
   id, ok = find_child(doc,parent_id,ident,index_map[parent_id])
   if !ok do index_map[parent_id] = 0
   else do index_map[parent_id] += 1
   return
}

get_argument_type :: proc(text: string) -> (type: Argument_Type) {
   switch text {
      case "new_id": type = .New_Id
      case "int": type = .Int
      case "uint": type = .Unsigned
      case "fixed": type = .Fixed
      case "string": type = .String
      case "object": type = .Object
      case "array": type = .Array
      case "fd": type = .Fd
   }
   return
}

find_attr :: xml.find_attribute_val_by_key
find_child :: xml.find_child_by_ident

after_underscore :: proc(s: string) -> string {
   index := strings.index_byte(s, '_')
   return s[index+1:]
}

parse_procedure :: proc(doc: ^xml.Document, id: u32, type: Procedure_Type, interface_name: string) -> Procedure {
   procedure := Procedure {
      name=get_name(doc,id),
      description=get_description(doc, id),
      type=type
   }
   type_name, found := find_attr(doc, id, "type")
   if !found do procedure.is_destructor = false
   else if type_name == "destructor" do procedure.is_destructor = true

   args : [dynamic]Argument
   log.debug("\t","Event:", procedure.name)
   for arg_id in iterate_child(doc, id, "arg") {
      arg := Argument {
         name = get_name(doc, arg_id),
      }
      enum_name, enum_found := find_attr(doc,id,"enum")
      if enum_found {
         arg.type = .Enum
         if strings.contains_rune(enum_name,'.') {
            // wl_output.transform -> output_transform
            enum_name, _ = strings.replace_all(after_underscore(enum_name), ".", "_")
         }
         arg.enum_name = fmt.aprintf("%v_%v", interface_name, enum_name)

      }
      interface_name, interface_found := find_attr(doc, arg_id, "interface")
      if interface_found {
         arg.interface_name = after_underscore(interface_name)
      }
      if !enum_found {
         type_name, type_found := find_attr(doc,arg_id,"type")
         if !type_found {
            // @Incomplete
         }
         arg.type = get_argument_type(type_name)
      }

      log.debug("\t\t","Argument:", arg.name)
      if arg.type == .New_Id && interface_found {
         procedure.ret = arg
      }
      else {
         if arg.type == .New_Id {
            procedure.new_id = arg
         }
         append(&args, arg)
      }
   }


   procedure.args = args[:]
   return procedure
}

get_argument_text :: proc(arg: Argument) -> string {
   sb: strings.Builder
   forward_text: string
   ret := false
   switch arg.type {
      case .Object:
         forward_text = arg.interface_name if arg.interface_name != "" else "rawptr"
      case .New_Id:
         if arg.interface_name != "" {
            forward_text = fmt.aprintf("^%v", arg.interface_name)
            ret = true
         }
         else {
            forward_text = "^interface, version: uint"
         }
      case .Enum:
         forward_text = arg.enum_name
      case .Int, .Fd:
         forward_text = "int"
      case .Unsigned:
         forward_text = "uint"
      case .Fixed:
         forward_text = "fixed_t"
      case .String:
         forward_text = "cstring"
      case .Array:
         forward_text = "array"
   }
   if !ret do fmt.sbprintf(&sb, "%v_: ", arg.name)
   fmt.sbprint(&sb, forward_text)
   return strings.to_string(sb)
}

// @Incomplete: error checking
read_file :: proc(filename: string) -> Protocol {
   doc, err := xml.load_from_file(filename)
   if err != nil {
      fmt.println("Error reading file:", filename)
      os.exit(1)
   }
   fmt.println("Parsing:", filename)
   protocol : Protocol
   name, found := find_attr(doc,0,"name"); assert(found)
   protocol.name = name
   interfaces: [dynamic]Interface
   for interface_id in iterate_child(doc,0,"interface") {
      interface_name := get_name(doc,interface_id)
      // Deprecated interfaces
      if interface_name == "wl_shell" || interface_name == "wl_shell_surface" do continue

      interface : Interface
      interface.name = after_underscore(interface_name)
      interface.unstripped_name = interface_name
      interface.description = get_description(doc, interface_id)
      requests : [dynamic]Procedure
      events : [dynamic]Procedure
      enums : [dynamic]Enumeration

      log.debug(interface.name)
      for request_id in iterate_child(doc,interface_id, "request") {
         request := parse_procedure(doc, request_id, .Request, interface.name)
         append(&requests, request)
      }
      for event_id in iterate_child(doc,interface_id,"event") {
         event := parse_procedure(doc, event_id, .Event, interface.name)
         append(&events, event)
      }
      for enum_id in iterate_child(doc, interface_id,"enum") {
         enumeration := Enumeration {
            name = get_name(doc, enum_id),
            description = get_description(doc, enum_id),

         }
         log.debug("\t","Enum:", enumeration.name)
         entries : [dynamic]Enum_Entry
         for entry_id in iterate_child(doc, enum_id, "entry") {
            value, found := find_attr(doc, entry_id, "value")
            if !found {
               // @Incomplete
            }
            name = get_name(doc, entry_id)
            if name[0] <= '9' && name[0] >= '0' {
               name = strings.concatenate({"_", name})
            }
            entry := Enum_Entry {
               name = name,
               value = value
            }
            append(&entries, entry)
            log.debug("\t\tEntry:", entry.name)
         }
         enumeration.entries = entries[:]
         append(&enums, enumeration)
      }
      interface.requests = requests[:]
      interface.events = events[:]
      interface.enums = enums[:]
      append(&interfaces, interface)
   }
   protocol.interfaces = interfaces[:]
   return protocol
}

generate_code :: proc(protocol: Protocol, package_name: string) -> string {
   sb: strings.Builder
   strings.write_string(&sb, "#+build linux\n")
   fmt.sbprintln(&sb,"package",package_name)
   for interface in protocol.interfaces {
         fmt.sbprintln(&sb, "/*", interface.description, "*/")
         fmt.sbprintfln(&sb,"%v :: struct {{}}", interface.name)
         fmt.sbprintfln(&sb,"%v_interface : interface", interface.name)
         fmt.sbprintfln(&sb,
`%[0]v_set_user_data :: proc "contextless" (%[0]v: ^%[0]v, user_data: rawptr) {{
   proxy_set_user_data(cast(^proxy)%[0]v, user_data)
}}

%[0]v_get_user_data :: proc "contextless" (%[0]v: ^%[0]v) -> rawptr {{
   return proxy_get_user_data(cast(^proxy)%[0]v)
}}
`, interface.name)
         has_destroy := false
         opcode := 0
         for request in interface.requests {
            has_ret := request.ret != nil
            has_new_id := request.new_id != nil
            fmt.sbprintln(&sb, "/*", request.description, "*/")

            opcode_name := fmt.aprintf("%v_%v", strings.to_upper(interface.name), strings.to_upper(request.name))
            fmt.sbprintfln(&sb,"%v :: %v",opcode_name, opcode)

            fmt.sbprintf(&sb, `%[0]v_%[1]v :: proc "contextless" (%[0]v: ^%[0]v`, interface.name, request.name)
            for arg in request.args do fmt.sbprintf(&sb, ", %v", get_argument_text(arg))
            fmt.sbprint(&sb, ") ")
            return_type := get_argument_text(request.ret.?) if has_ret else "rawptr"

            if has_ret || has_new_id do fmt.sbprintf(&sb,"-> %v ",return_type)
            fmt.sbprintln(&sb, "{")
            fmt.sbprint(&sb, "\t")
            if has_ret || has_new_id do fmt.sbprint(&sb, "ret := ")
            fmt.sbprintf(&sb, "proxy_marshal_flags(cast(^proxy)%v, %v", interface.name, opcode_name)

            if has_ret do fmt.sbprintf(&sb, ", &%[0]v_interface, proxy_get_version(cast(^proxy)%[0]v)", interface.name)
            else if has_new_id do fmt.sbprintf(&sb, ", %v_, version", request.new_id.?.name)
            else do fmt.sbprintf(&sb, ", nil, proxy_get_version(cast(^proxy)%v)", interface.name)

            fmt.sbprint(&sb, ", 1" if request.is_destructor else ", 0")

            if has_ret do fmt.sbprint(&sb, ", nil")
            for arg in request.args {
               fmt.sbprintf(&sb, ", %v_", arg.name)
               if arg.type == .New_Id do fmt.sbprint(&sb, ".name, version")
            }
            fmt.sbprintln(&sb, ")")
            if has_ret || has_new_id {
               fmt.sbprintfln(&sb, "\treturn cast(%v)ret", return_type)
            }
            fmt.sbprintln(&sb, "}")
            if request.name == "destroy" do has_destroy = true
            opcode += 1
         }
         if !has_destroy && interface.name != "display" {
            fmt.sbprintfln(&sb,
`%[0]v_destroy :: proc "contextless" (%[0]v: ^%[0]v) {{
   proxy_destroy(cast(^proxy)%[0]v)
}}
`, interface.name)
         }
         if len(interface.events) != 0 {
            fmt.sbprintfln(&sb, "%v_listener :: struct {{",interface.name)
            for event in interface.events {
               fmt.sbprintln(&sb, "/*", event.description, "*/")

               fmt.sbprint(&sb, "\t")
               fmt.sbprintf(&sb,`%v : proc "c" (data: rawptr, %v: ^%v`, event.name, interface.name, interface.name)
               for arg, i in event.args {
                  fmt.sbprintf(&sb, ", %v",get_argument_text(arg))

               }
               if event.ret != nil do fmt.sbprintfln(&sb, ") -> %v,\n", get_argument_text(event.ret.?))
               else do fmt.sbprintln(&sb, "),\n")
            }
            fmt.sbprintln(&sb, "}")
            fmt.sbprintfln(&sb, `%v_add_listener :: proc "contextless" (%[0]v: ^%[0]v, listener: ^%[0]v_listener, data: rawptr) {{`,interface.name)
            fmt.sbprintfln(&sb, "\tproxy_add_listener(cast(^proxy)%v, cast(^generic_c_call)listener,data)", interface.name)
            fmt.sbprintln(&sb, "}")
         }
         for enumeration in interface.enums {
            fmt.sbprintln(&sb, "/*", enumeration.description, "*/")
            fmt.sbprintfln(&sb, "%v_%v :: enum {{", interface.name, enumeration.name)
            for entry in enumeration.entries {
               fmt.sbprintfln(&sb, "\t%v = %v,", entry.name, entry.value)
            }
            fmt.sbprintln(&sb, "}")
         }

   }

   fmt.sbprintln(&sb, "\n// Functions from libwayland-client")
   if protocol.name == "wayland" {
      fmt.sbprintln(&sb, `import "core:c"`)
      fmt.sbprintln(&sb,`foreign import wl_lib "system:wayland-client"`)

      strings.write_string(&sb,
`@(default_calling_convention="c")
@(link_prefix="wl_")
foreign wl_lib {
   display_connect                           :: proc(name: cstring) -> ^display ---
   display_connect_to_fd                     :: proc(fd: int) -> ^display ---
   display_disconnect                        :: proc(display: ^display) ---
   display_get_fd                            :: proc(display: ^display) -> int ---
   display_dispatch                          :: proc(display: ^display) -> int ---
   display_dispatch_queue                    :: proc(display: ^display, queue: event_queue) -> int ---
   display_dispatch_queue_pending            :: proc(display: ^display, queue: event_queue) -> int ---
   display_dispatch_pending                  :: proc(display: ^display) -> int ---
   display_get_error                         :: proc(display: ^display) -> int ---
   display_get_protocol_error                :: proc(display: ^display, intf: ^interface, id: ^u32) -> u32 ---
   display_flush                             :: proc(display: ^display) -> int ---
   display_roundtrip_queue                   :: proc(display: ^display, queue: ^event_queue) -> int ---
   display_roundtrip                         :: proc(display: ^display) -> int ---
   display_create_queue                      :: proc(display: ^display) -> ^event_queue ---
   display_prepare_read_queue                :: proc(display: ^display, queue: ^event_queue) -> int ---
   display_prepare_read                      :: proc(display: ^display) -> int ---
   display_cancel_read                       :: proc(display: ^display) ---
   display_read_events                       :: proc(display: ^display) -> int ---
   display_set_max_buffer_size               :: proc(display: ^display, max_buffer_size: c.size_t) ---

   proxy_marshal_flags                       :: proc(p: ^proxy, opcode: uint, intf: ^interface, version: uint, flags: uint, args: ..any) -> ^proxy ---
   proxy_marshal_array_flags                 :: proc(p: ^proxy, opcode: uint, intf: ^interface, version: uint, flags: uint, args: ^argument) -> ^proxy ---
   proxy_marshal                             :: proc(p: ^proxy, opcode: uint, args: ..any) ---
   proxy_marshal_array                       :: proc(p: ^proxy, opcode: uint, args: ^argument) ---
   proxy_create                              :: proc(factory: ^proxy, intf: ^interface) -> ^proxy ---
   proxy_create_wrapper                      :: proc(proxy: rawptr) -> rawptr ---
   proxy_wrapper_destroy                     :: proc(proxy_wrapper: rawptr) ---
   proxy_marshal_constructor                 :: proc(p: ^proxy, opcode: uint, intf: ^interface, args: ..any) -> ^proxy ---
   proxy_marshal_constructor_versioned       :: proc(p: ^proxy, opcode: uint, intf: ^interface, version: uint, args: ..any) -> ^proxy ---
   proxy_marshal_array_constructor           :: proc(p: ^proxy, opcode: uint, args: ^argument, intf: ^interface) -> ^proxy ---
   proxy_marshal_array_constructor_versioned :: proc(p: ^proxy, opcode: uint, args: ^argument, intf: ^interface, version: uint) -> ^proxy ---
   proxy_destroy                             :: proc(p: ^proxy) ---
   proxy_add_listener                        :: proc(p: ^proxy, impl: ^generic_c_call, data: rawptr) -> int ---
   proxy_get_listener                        :: proc(p: ^proxy) -> rawptr ---
   proxy_add_dispatcher                      :: proc(p: ^proxy, func: dispatcher_func_t, dispatcher_data: rawptr, data: rawptr) -> int ---
   proxy_set_user_data                       :: proc(p: ^proxy, user_data: rawptr) ---
   proxy_get_user_data                       :: proc(p: ^proxy) -> rawptr ---
   proxy_get_version                         :: proc(p: ^proxy) -> uint ---
   proxy_get_id                              :: proc(p: ^proxy) -> uint ---
   proxy_set_tag                             :: proc(p: ^proxy, tag: ^u8) ---
   proxy_get_tag                             :: proc(p: ^proxy) -> ^u8 ---
   proxy_get_class                           :: proc(p: ^proxy) -> ^u8 ---
   proxy_set_queue                           :: proc(p: ^proxy, queue: ^event_queue) ---
}`)
   }
   else {
      fmt.sbprintln(&sb, `import wl "shared:wayland"`)
      add_wl_name(&sb, "fixed_t")
      add_wl_name(&sb, "array")
      add_wl_name(&sb, "generic_c_call")
      add_wl_name(&sb, "proxy_add_listener")
      add_wl_name(&sb, "proxy_get_listener")
      add_wl_name(&sb, "proxy_get_user_data")
      add_wl_name(&sb, "proxy_set_user_data")
      add_wl_name(&sb, "proxy_marshal")
      add_wl_name(&sb, "proxy_marshal_array")
      add_wl_name(&sb, "proxy_marshal_flags")
      add_wl_name(&sb, "proxy_marshal_array_flags")
      add_wl_name(&sb, "proxy_marshal_constructor")
      add_wl_name(&sb, "proxy_destroy")
   }

   return strings.to_string(sb)
}

add_wl_name :: proc(sb: ^strings.Builder, func_name: string, private:= true) {
   if private do fmt.sbprintln(sb, "@(private)")
   fmt.sbprintfln(sb, "%v :: wl.%v", func_name)
}
main :: proc() {
   options : struct {
      input: string `args:"pos=0,required" usage:"Wayland xml protocol path."`,
		output: string `args:"pos=1" usage:"Odin output path."`,
      package_name: string `args:"pos=2" usage:"Package name for output code"`,
		verbose: bool `args:"pos=3" usage:"Show verbose output."`,
   }
   style := flags.Parsing_Style.Odin
   flags.parse_or_exit(&options, os.args, style)
   context.logger = log.create_console_logger(opt={}) if options.verbose else log.Logger{}
   protocol := read_file(options.input)
   output_filename : string
   if options.output != "" {
      output_filename = options.output
   }
   else {
      output_filename = strings.concatenate({filepath.stem(options.input), ".odin"})
   }
   fmt.println("Outputting to:", output_filename)

   package_name := options.package_name if options.package_name != "" else protocol.name
   code := generate_code(protocol, package_name)
   if !os.write_entire_file(output_filename, transmute([]u8)code) {
      fmt.println("There was an error outputting to the file:", os.get_last_error())
      return
   }
   fmt.println("Done")
}
