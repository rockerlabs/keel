- `extract_dir_tickets` (`tools/lib/dir-tickets.sh`) now joins a `+`-joined ticket list wrapped across a line
  break (`dir #1 +` then `#2`) the way it already joined a comma-wrapped one (dir #589): the line-end buffer
  trigger and the continuation pattern both accept `+`, matching the `+` dir #482 added to the grep anchor.
