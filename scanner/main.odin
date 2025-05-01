package wayland_scanner
import "core:fmt"
import "core:encoding/xml"
import "core:log"
import "core:strings"

Procedure :: struct {
   description: string,
   name: string,
   type: enum {
      Request,
      Event,
   },
   args: []Argument
}

Entry :: struct {
   name: string,
   value: string,
}

Enumeration :: struct {
   name: string,
   entires: []Entry
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
}
Argument :: struct {
   name: string,
   type: Argument_Type,

   nullable: bool,
   interface_name: string,
   // TODO: summary: string
}

get_description :: proc(doc: ^xml.Document, id: u32) -> string {
   desc_id,found := find_child(doc, id, "description")
   if !found {
      return ""
   }
   return doc.elements[desc_id].value[0].(string)
}
get_name :: proc(doc: ^xml.Document, id: u32) -> string {
   name, found := find_attr(doc,id,"name")
   return name
}

iterate_child :: proc(doc: ^xml.Document, parent_id: u32, ident: string) -> (id: u32, ok: bool) {
   @(static) index_map : map[u32]int
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
   defer delete(interfaces)
   for interface_id in iterate_child(doc,0,"interface") {
      name := get_name(doc,interface_id)
      log.debug(name)
      interface : Interface
      interface.name = name
      interface.description = get_description(doc, interface_id)
      requests : [dynamic]Procedure
      events : [dynamic]Procedure
      enums : [dynamic]Enumeration
      for request_id in iterate_child(doc,interface_id, "request") {
         log.debug("\t","Request:", get_name(doc,request_id))
         for arg_id in iterate_child(doc, request_id, "arg") {
            log.debug("\t\t","Argument:", get_name(doc, arg_id))
         }
      }
      for event_id in iterate_child(doc,interface_id,"event") {
         log.debug("\t","Event:", get_name(doc,event_id))
         for arg_id in iterate_child(doc, event_id, "arg") {

            log.debug("\t\t","Argument:", get_name(doc, arg_id))
         }
      }
      for enum_id in iterate_child(doc, interface_id,"enum") {
         name = get_name(doc, enum_id)
         log.debug("\t","Enum:", name)
         for entry_id in iterate_child(doc, enum_id, "entry") {
            log.debug("\t\t","Entry:", get_name(doc,entry_id))
         }
      }
      interface.requests = requests[:]
      interface.events = events[:]
      free_all(context.temp_allocator)
      append(&interfaces, interface)
   }
   protocol.interfaces = interfaces[:]
   return protocol
}

main :: proc() {
   context.logger = log.create_console_logger(opt={.Level})
   protocol := read_file("protocol/wayland.xml")
}
