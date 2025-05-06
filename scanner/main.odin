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
   args: []Argument
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
   enumerations: []Enumeration,
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
   Interface,
   Enum,
}
Argument :: struct {
   name: string,
   type: Argument_Type,

   nullable: bool,

   // If type is either of them
   interface_name: string,
   enum_name: string
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
find_attr :: xml.find_attribute_val_by_key
find_child :: xml.find_child_by_ident

parse_argument :: proc(doc: ^xml.Document, id:  u32) -> Argument {
   arg := Argument {
      name = get_name(doc, id),
   }
   enum_name, enum_found := find_attr(doc,id,"enum")
   if enum_found {
      arg.type = .Enum
      arg.enum_name = enum_name
   }
   interface_name, interface_found := find_attr(doc, id, "interface")
   if interface_found {
      arg.type = .Interface
      arg.interface_name = interface_name

   }
   if !enum_found && !interface_found {
      type_name, type_found := find_attr(doc,id,"type")
      if !type_found {
         // @Incomplete
      }
      arg.type = get_argument_type(type_name)
   }

   log.debug("\t\t","Argument:", arg.name)
   return arg
}

parse_procedure :: proc(doc: ^xml.Document, id: u32, type: Procedure_Type) -> Procedure {
   procedure := Procedure {
      name=get_name(doc,id),
      description=get_description(doc, id),
      type=type
   }
   args : [dynamic]Argument
   log.debug("\t","Event:", procedure.name)
   for arg_id in iterate_child(doc, id, "arg") {
      arg := parse_argument(doc, arg_id)
      append(&args, arg)
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
      interface.name = get_name(doc,interface_id)
      interface.description = get_description(doc, interface_id)
      requests : [dynamic]Procedure
      events : [dynamic]Procedure
      enums : [dynamic]Enumeration
      log.debug(interface.name)
      for request_id in iterate_child(doc,interface_id, "request") {
         request := parse_procedure(doc, request_id, .Request)
         append(&requests, request)
      }
      for event_id in iterate_child(doc,interface_id,"event") {
         event := parse_procedure(doc, event_id, .Event)
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
      }
      interface.requests = requests[:]
      interface.events = events[:]
      interface.enumerations = enums[:]
      append(&interfaces, interface)
   }
   protocol.interfaces = interfaces[:]
   return protocol
}

generate_code :: proc(protocol: Protocol) -> string {
   builder: strings.Builder
   strings.write_string(&builder, "#+build linux\n")
   fmt.sbprintln(&builder,"package",protocol.name)
   for interface in protocol.interfaces {
         underscore_index := strings.index_byte(interface.name, '_')
         stripped_name := interface.name[underscore_index+1:]

         // This is actually wrong but doesn't matter
         fmt.sbprintln(&builder,stripped_name,":: distinct interface")
   }
   if protocol.name == "wayland" {
      fmt.sbprintln(&builder, `import "core:c"`)
      fmt.sbprintln(&builder,`foreign import wl_lib "system:wayland-client"`)

      strings.write_string(&builder,
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

   return strings.to_string(builder)
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
