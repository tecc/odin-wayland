package wayland_scanner
import "core:fmt"
import "core:encoding/xml"
import "core:log"
import "core:strings"
import "base:runtime"
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
      log.error("Error reading file:", filename)
      return {}
   }
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


main :: proc() {
   context.logger = log.create_console_logger(opt={.Level})
   protocol := read_file("../protocols/wayland.xml")
   log.debug("Done")
}
