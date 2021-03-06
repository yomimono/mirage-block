(*
 * Copyright (C) 2015 David Scott <dave.scott@docker.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)
open Lwt
open Mirage_block_log

let fatalf fmt = Printf.ksprintf (fun s ->
    err (fun f -> f "%s" s);
    return (`Error (`Unknown s))
  ) fmt

let check_buffer op sector_size b =
  let open Mirage_block_monad.Infix in
  (* Check buffers are whole numbers of sectors *)
  ( let len = Cstruct.len b in
    if len mod sector_size <> 0
    then fatalf "%s: buffer length (%d) is not a multiple of sector_size (%d)" op len sector_size
    else Lwt.return (`Ok ()) )
  >>= fun () ->
  (* TODO: Check buffers are sector-aligned *)
  Lwt.return (`Ok ())

let rec check_buffers op sector_size = function
  | [] -> Lwt.return (`Ok ())
  | b :: bs ->
    let open Mirage_block_monad.Infix in
    check_buffer op sector_size b
    >>= fun () ->
    check_buffers op sector_size bs

let check_in_range op size_sectors offset =
  if offset < 0L || offset >= size_sectors
  then fatalf "%s: sector offset out of range 0 <= %Ld < %Ld" op offset size_sectors
  else Lwt.return (`Ok ())

let check op sector_size size_sectors offset buffers =
  let open Mirage_block_monad.Infix in
  check_buffers op sector_size buffers
  >>= fun () ->
  check_in_range op size_sectors offset
  >>= fun () ->
  let length = List.fold_left (fun acc b -> Cstruct.len b + acc) 0 buffers in
  let next_sector = Int64.(add offset (of_int @@ length / sector_size)) in
  if next_sector > size_sectors
  then fatalf "%s: sector offset out of range %Ld > %Ld" op next_sector size_sectors
  else Lwt.return (`Ok ())

module BLOCK(B: V1_LWT.BLOCK) = struct
  include B

  let unsafe_read = read
  let unsafe_write = write

  let read t offset buffers =
    let open Lwt.Infix in
    B.get_info t
    >>= fun info ->
    let open Mirage_block_monad.Infix in
    check "read" info.sector_size info.size_sectors offset buffers
    >>= fun () ->
    unsafe_read t offset buffers

  let write t offset buffers =
    let open Lwt.Infix in
    B.get_info t
    >>= fun info ->
    let open Mirage_block_monad.Infix in
    check "write" info.sector_size info.size_sectors offset buffers
    >>= fun () ->
    unsafe_write t offset buffers
end
