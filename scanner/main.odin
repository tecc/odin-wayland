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
   ret: Argument,
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
   name, found := find_attr(doc,id,"name")
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

get_argument_text :: proc(arg: Argument) -> string {
   sb: strings.Builder
   fmt.sbprintf(&sb, "%v: ", arg.name)
   type_text: string
   switch arg.type {
      case .New_Id, .Object:
         type_text = arg.interface_name if arg.interface_name != "" else "rawptr"
      case .Enum:
         type_text = arg.enum_name
      case .Int, .Fd:
         type_text = "int"
      case .Unsigned:
         type_text = "uint"
      case .Fixed:
         type_text = "fixed_t"
      case .String:
         type_text = "cstring"
      case .Array:
         type_text = "array"
   }
   fmt.sbprint(&sb, type_text)
   return strings.to_string(sb)
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
         name = get_name(doc, id),
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
      interface_name, interface_found := find_attr(doc, id, "interface")
      if interface_found {
         arg.interface_name = after_underscore(interface_name)
      }
      if !enum_found {
         type_name, type_found := find_attr(doc,id,"type")
         if !type_found {
            // @Incomplete
         }
         arg.type = get_argument_type(type_name)
      }

      log.debug("\t\t","Argument:", arg.name)
      if arg.type == .New_Id {
         procedure.ret = arg
      }
      else {
         append(&args, arg)
      }
   }


   procedure.args = args[:]
   return procedure
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
      interface : Interface
      interface.name = after_underscore(get_name(doc,interface_id))
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

            entry := Enum_Entry {
               name = get_name(doc,entry_id),
               value = value
            }
            append(&entries, entry)
            log.debug("\t\t","Entry:", entry.name)
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

generate_code :: proc(protocol: Protocol) -> string {
   sb: strings.Builder
   strings.write_string(&sb, "#+build linux\n")
   fmt.sbprintln(&sb,"package",protocol.name)
   for interface in protocol.interfaces {
         fmt.sbprintfln(&sb,"%v :: struct {{}}", interface.name)
         fmt.sbprintfln(&sb,"%v_interface : interface", interface.name)
         fmt.sbprintfln(&sb,
`%[0]v_set_user_data :: proc(%[0]v: ^%[0]v, user_data: rawptr) {{
   proxy_set_user_data(cast(^proxy)%[0]v, user_data)
}}

%[0]v_get_user_data :: proc(%[0]v: ^%[0]v) -> rawptr {{
   return proxy_get_user_data(cast(^proxy)%[0]v)
}}
`, interface.name)
         has_destroy := false
         opcode := 0
         for request in interface.requests {
            upper_interface_name := strings.to_upper(interface.name)
            upper_request_name := strings.to_upper(request.name)
            fmt.sbprintfln(&sb,"%v_%v :: %v",upper_interface_name, upper_request_name, opcode)

            if request.name == "destroy" do has_destroy = true


            if request.is_destructor {

            }
            opcode += 1
         }
         if !has_destroy && interface.name != "display" {
            fmt.sbprintfln(&sb,
`%[0]v_destroy :: proc(%[0]v: ^%[0]v) {{
   proxy_destroy(cast(^proxy)%[0]v)
}}
`, interface.name)
         }
         if len(interface.events) != 0 {
            fmt.sbprintfln(&sb, "%v_listener :: struct {{",interface.name)
            for event in interface.events {
               fmt.sbprintf(&sb,"\t%v : proc(data: rawptr, %v: %v", event.name, interface.name, interface.name)
               for arg, i in event.args {
                  fmt.sbprintf(&sb, ", %v",get_argument_text(arg))
               }

               fmt.sbprintln(&sb, ") -> rawptr,")
            }
            fmt.sbprintln(&sb, "}")
            fmt.sbprintfln(&sb, "%v_add_listener :: proc(%[0]v: ^%[0]v, listener: ^%[0]v_listener, data: rawptr) {{",interface.name)
            fmt.sbprintfln(&sb, "\tproxy_add_listener(cast(^proxy)%v, cast(^generic_c_call)listener,data)", interface.name)
            fmt.sbprintln(&sb, "}")
         }
         for enumeration in interface.enums {
            fmt.sbprintfln(&sb, "%v_%v :: enum {{", interface.name, enumeration.name)
            fmt.sbprintln(&sb, "}")
         }

   }
   if protocol.name == "wayland" {
      fmt.sbprintln(&sb, `import "core:c"`)
      fmt.sbprintln(&sb,`foreign import wl_lib "system:wayland-client"`)

      strings.write_string(&sb,
`@(default_calling_convention="c")
@(link_prefix="wl_")
foreign wl_lib {
   display_connect                           :: proc(name: cstring) -> ^display ---
   display_connect_to_fd                     :: proc(fd: i32) -> ^display ---
   display_disconnect                        :: proc(display: ^display) ---
   display_get_fd                            :: proc(display: ^display) -> i32 ---
   display_dispatch                          :: proc(display: ^display) -> i32 ---
   display_dispatch_queue                    :: proc(display: ^display, queue: event_queue) -> i32 ---
   display_dispatch_queue_pending            :: proc(display: ^display, queue: event_queue) -> i32 ---
   display_dispatch_pending                  :: proc(display: ^display) -> i32 ---
   display_get_error                         :: proc(display: ^display) -> i32 ---
   display_get_protocol_error                :: proc(display: ^display, intf: ^interface, id: ^u32) -> u32 ---
   display_flush                             :: proc(display: ^display) -> i32 ---
   display_roundtrip_queue                   :: proc(display: ^display, queue: ^event_queue) -> i32 ---
   display_roundtrip                         :: proc(display: ^display) -> i32 ---
   display_create_queue                      :: proc(display: ^display) -> ^event_queue ---
   display_prepare_read_queue                :: proc(display: ^display, queue: ^event_queue) -> i32 ---
   display_prepare_read                      :: proc(display: ^display) -> i32 ---
   display_cancel_read                       :: proc(display: ^display) ---
   display_read_events                       :: proc(display: ^display) -> i32 ---
   display_set_max_buffer_size               :: proc(display: ^display, max_buffer_size: c.size_t) ---

   proxy_marshal_flags                       :: proc(p: ^proxy, opcode: u32, intf: ^interface, version: u32, flags: u32, args: ..any) -> ^proxy ---
   proxy_marshal_array_flags                 :: proc(p: ^proxy, opcode: u32, intf: ^interface, version: u32, flags: u32, args: ^argument) -> ^proxy ---
   proxy_marshal                             :: proc(p: ^proxy, opcode: u32, args: ..any) ---
   proxy_marshal_array                       :: proc(p: ^proxy, opcode: u32, args: ^argument) ---
   proxy_create                              :: proc(factory: ^proxy, intf: ^interface) -> ^proxy ---
   proxy_create_wrapper                      :: proc(proxy: rawptr) -> rawptr ---
   proxy_wrapper_destroy                     :: proc(proxy_wrapper: rawptr) ---
   proxy_marshal_constructor                 :: proc(p: ^proxy, opcode: u32, intf: ^interface, args: ..any) -> ^proxy ---
   proxy_marshal_constructor_versioned       :: proc(p: ^proxy, opcode: u32, intf: ^interface, version: u32, args: ..any) -> ^proxy ---
   proxy_marshal_array_constructor           :: proc(p: ^proxy, opcode: u32, args: ^argument, intf: ^interface) -> ^proxy ---
   proxy_marshal_array_constructor_versioned :: proc(p: ^proxy, opcode: u32, args: ^argument, intf: ^interface, version: u32) -> ^proxy ---
   proxy_destroy                             :: proc(p: ^proxy) ---
   proxy_add_listener                        :: proc(p: ^proxy, impl: ^generic_c_call, data: rawptr) -> i32 ---
   proxy_get_listener                        :: proc(p: ^proxy) -> rawptr ---
   proxy_add_dispatcher                      :: proc(p: ^proxy, func: dispatcher_func_t, dispatcher_data: rawptr, data: rawptr) -> i32 ---
   proxy_set_user_data                       :: proc(p: ^proxy, user_data: rawptr) ---
   proxy_get_user_data                       :: proc(p: ^proxy) -> rawptr ---
   proxy_get_version                         :: proc(p: ^proxy) -> u32 ---
   proxy_get_id                              :: proc(p: ^proxy) -> u32 ---
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

add_wl_name :: proc(sb: ^strings.Builder, func_name: string) {
   fmt.sbprintln(sb, "@(private)")
   fmt.sbprintfln(sb, "%v :: wl.%v", func_name)
}
main :: proc() {
   options : struct {
      input: string `args:"pos=0,required" usage:"Wayland xml protocol path."`,
		output: string `args:"pos=1" usage:"Odin output path."`,
		verbose: bool `args:"pos=2" usage:"Show verbose output."`,
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
   code := generate_code(protocol)
   if !os.write_entire_file(output_filename, transmute([]u8)code) {
      fmt.println("There was an error outputting to the file:", os.get_last_error())
      return
   }
   fmt.println("Done")
}
