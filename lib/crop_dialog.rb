# frozen_string_literal: true

require 'adwaita'

# CropDialog lets the user pick a square region of an image to use as an avatar.
#
# Ported from upstream's src/contacts-crop-dialog.vala and the Cc.CropArea
# widget it embeds (src/cc-crop-area.c). The crop region is always square,
# because that is what the avatar is rendered as; it can be dragged to
# reposition and resized from its corners.
#
class CropDialog < Adwaita::Dialog
  MIN_SIZE = 48
  HANDLE = 16

  def initialize(pixbuf, on_cropped)
    super()
    self.title = 'Crop Image'
    self.content_width = 520
    self.content_height = 560
    @pixbuf = pixbuf
    @on_cropped = on_cropped
    @scale = 1.0
    @offset = [0, 0]
    reset_crop
  end

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |tv|
        tv.add_top_bar(header_bar)
        tv.content = crop_area

        header_bar.tap do |hb|
          hb.pack_start(cancel_button)
          hb.pack_end(select_button)

          cancel_button.signal_connect('clicked') { close }
          select_button.signal_connect('clicked') { emit_cropped }
        end

        crop_area.tap do |area|
          area.set_draw_func { |_, cr, width, height| draw(cr, width, height) }
          area.add_controller(drag_gesture)

          drag_gesture.tap do |gesture|
            gesture.signal_connect('drag-begin') { |_, x, y| begin_drag(x, y) }
            gesture.signal_connect('drag-update') { |_, dx, dy| update_drag(dx, dy) }
          end
        end
      end
    end
  end

  # Memoized widget methods

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def cancel_button
    @cancel_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Cancel'
      btn.use_underline = true
    end
  end

  def select_button
    @select_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Select'
      btn.use_underline = true
      btn.add_css_class('suggested-action')
    end
  end

  def crop_area
    @crop_area ||= Gtk::DrawingArea.new.tap do |area|
      area.hexpand = true
      area.vexpand = true
      area.margin_top = 12
      area.margin_bottom = 12
      area.margin_start = 12
      area.margin_end = 12
    end
  end

  def drag_gesture = @drag_gesture ||= Gtk::GestureDrag.new

  private

  # Start with the largest centred square the image allows, as upstream does.
  def reset_crop
    [@pixbuf.width, @pixbuf.height].min.then do |side|
      @crop = { x: (@pixbuf.width - side) / 2, y: (@pixbuf.height - side) / 2, size: side }
    end
  end

  # --- Drawing ------------------------------------------------------------

  def draw(cairo, width, height)
    fit(width, height)
    cairo.save
    cairo.translate(@offset[0], @offset[1])
    cairo.scale(@scale, @scale)
    cairo.set_source_pixbuf(@pixbuf, 0, 0)
    cairo.paint
    cairo.restore

    shade_outside(cairo, width, height)
    outline_crop(cairo)
  end

  # Letterbox the image into the widget and remember the transform, so screen
  # coordinates from the gesture can be mapped back to image pixels.
  def fit(width, height)
    @scale = [width.to_f / @pixbuf.width, height.to_f / @pixbuf.height].min
    @offset = [(width - (@pixbuf.width * @scale)) / 2.0, (height - (@pixbuf.height * @scale)) / 2.0]
  end

  def shade_outside(cairo, width, height)
    cairo.save
    cairo.set_source_rgba(0, 0, 0, 0.6)
    cairo.rectangle(0, 0, width, height)
    screen_crop.then { |x, y, size| cairo.rectangle(x + size, y, -size, size) }
    cairo.set_fill_rule(:even_odd)
    cairo.fill
    cairo.restore
  end

  def outline_crop(cairo)
    cairo.save
    screen_crop.then do |x, y, size|
      cairo.set_source_rgba(1, 1, 1, 0.9)
      cairo.set_line_width(1.5)
      cairo.rectangle(x, y, size, size)
      cairo.stroke

      # Corner handles, so it is discoverable that the square can be resized.
      cairo.set_line_width(3)
      [[x, y, 1, 1], [x + size, y, -1, 1], [x, y + size, 1, -1], [x + size, y + size, -1, -1]]
        .each do |cx, cy, sx, sy|
          cairo.move_to(cx + (HANDLE * sx), cy)
          cairo.line_to(cx, cy)
          cairo.line_to(cx, cy + (HANDLE * sy))
          cairo.stroke
        end
    end
    cairo.restore
  end

  def screen_crop
    [@offset[0] + (@crop[:x] * @scale), @offset[1] + (@crop[:y] * @scale), @crop[:size] * @scale]
  end

  # --- Dragging -----------------------------------------------------------

  def begin_drag(x, y)
    @drag_origin = @crop.dup
    @drag_corner = corner_at(x, y)
  end

  # A drag started near a corner resizes; anywhere else moves the square.
  def corner_at(x, y)
    screen_crop.then do |cx, cy, size|
      { top_left: [cx, cy], top_right: [cx + size, cy],
        bottom_left: [cx, cy + size], bottom_right: [cx + size, cy + size] }
        .find { |_, (px, py)| ((px - x).abs < HANDLE) && ((py - y).abs < HANDLE) }&.first
    end
  end

  def update_drag(dx, dy)
    [dx / @scale, dy / @scale].then do |ix, iy|
      @drag_corner ? resize_crop(ix, iy) : move_crop(ix, iy)
    end
    crop_area.queue_draw
  end

  def move_crop(dx, dy)
    @crop[:x] = clamp(@drag_origin[:x] + dx, 0, @pixbuf.width - @crop[:size])
    @crop[:y] = clamp(@drag_origin[:y] + dy, 0, @pixbuf.height - @crop[:size])
  end

  # Resizing keeps the square anchored at the corner opposite the one dragged.
  def resize_crop(dx, dy)
    delta_for(@drag_corner, dx, dy).then do |delta|
      clamp(@drag_origin[:size] + delta, MIN_SIZE, max_size_for(@drag_corner)).then do |size|
        @crop[:size] = size
        @crop[:x] = anchor_x(size)
        @crop[:y] = anchor_y(size)
      end
    end
  end

  def delta_for(corner, dx, dy)
    case corner
    when :bottom_right then [dx, dy].min
    when :bottom_left then [-dx, dy].min
    when :top_right then [dx, -dy].min
    else [-dx, -dy].min
    end
  end

  def max_size_for(corner)
    [horizontal_room(corner), vertical_room(corner)].min
  end

  def horizontal_room(corner)
    %i[bottom_right top_right].include?(corner) ? @pixbuf.width - @drag_origin[:x] : @drag_origin[:x] + @drag_origin[:size]
  end

  def vertical_room(corner)
    %i[bottom_right bottom_left].include?(corner) ? @pixbuf.height - @drag_origin[:y] : @drag_origin[:y] + @drag_origin[:size]
  end

  def anchor_x(size)
    %i[bottom_right top_right].include?(@drag_corner) ? @drag_origin[:x] : @drag_origin[:x] + @drag_origin[:size] - size
  end

  def anchor_y(size)
    %i[bottom_right bottom_left].include?(@drag_corner) ? @drag_origin[:y] : @drag_origin[:y] + @drag_origin[:size] - size
  end

  def clamp(value, low, high) = [[value, low].max, [high, low].max].min

  # --- Result -------------------------------------------------------------

  def emit_cropped
    cropped_avatar.then do |avatar|
      @on_cropped.call(avatar) if avatar
      close
    end
  end

  def cropped_avatar
    @pixbuf.subpixbuf(@crop[:x].to_i, @crop[:y].to_i, @crop[:size].to_i, @crop[:size].to_i)
           .scale_simple(Avatar::STORED_SIZE, Avatar::STORED_SIZE, :bilinear)
           .then { |scaled| Avatar.new(data: scaled.save('png'), media_type: 'image/png') }
  rescue StandardError, GLib::Error => e
    warn "Could not crop avatar: #{e.message}"
    nil
  end
end
