# frozen_string_literal: true

require 'adwaita'
require 'ashpd'
require 'stringio'
require_relative 'crop_dialog'

# AvatarSelector offers a grid of stock avatars plus a "choose a file" button.
#
# Ported from upstream's src/contacts-avatar-selector.vala, which gets a
# Xdp::Portal from libportal and, on the camera button, calls
# `portal.access_camera` followed by `portal.open_pipewire_remote_for_camera`
# to pull frames off a PipeWire stream. The `ashpd` gem binds the same XDG
# desktop portal, but as far as `Ashpd::Camera.present?` — a presence check —
# and nothing that opens the camera stream or hands back a PipeWire fd, so
# there is no way to port the actual capture. What IS real here: the camera
# button's enabled state is the live `Ashpd::Camera.present?` portal call
# upstream also makes to decide this (contacts-avatar-selector.vala's
# `setup_camera_portal`); clicking it says plainly that capture itself isn't
# available through this binding, rather than silently doing nothing. A file
# chosen through "Choose a File…" is handed to CropDialog exactly as upstream
# does.
#
class AvatarSelector < Adwaita::Dialog
  ICON_SIZE = 64
  STOCK_ICONS = %w[
    avatar-default-symbolic face-smile-symbolic face-laugh-symbolic
    face-cool-symbolic face-wink-symbolic face-glasses-symbolic
    face-angel-symbolic face-monkey-symbolic emote-love-symbolic
  ].freeze

  def initialize(contact, on_selected)
    super()
    self.title = 'Select Avatar'
    self.content_width = 420
    self.content_height = 460
    @contact = contact
    @on_selected = on_selected
  end

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |tv|
        tv.add_top_bar(header_bar)
        tv.content = scroller

        header_bar.tap do |hb|
          hb.pack_start(file_button)
          hb.pack_start(camera_button)
          hb.pack_end(remove_button)

          file_button.signal_connect('clicked') { choose_file }
          camera_button.signal_connect('clicked') { report_no_capture }
          remove_button.signal_connect('clicked') { select(nil) }
        end

        scroller.tap do |sw|
          sw.child = content_box

          content_box.tap do |box|
            box.append(thumbnail_grid)

            thumbnail_grid.tap do |grid|
              STOCK_ICONS.each { |icon| grid.append(thumbnail_for(icon)) }
              grid.signal_connect('child-activated') { |_, child| select(child.avatar_data) }
            end
          end
        end
      end
    end
  end

  # Memoized widget methods

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def file_button
    @file_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'document-open-symbolic'
      btn.tooltip_text = 'Choose a File…'
    end
  end

  def remove_button
    @remove_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'user-trash-symbolic'
      btn.tooltip_text = 'Remove Avatar'
    end
  end

  # Upstream's camera_button, gated by the same real portal presence check
  # (`Ashpd::Camera.present?`, upstream's `portal.is_camera_present()`) rather
  # than a hardcoded true/false. Insensitive whenever the check fails, be it
  # "no camera" or no portal backend to ask at all (this dev shell, CI).
  def camera_button
    @camera_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'camera-photo-symbolic'
      present, reason = camera_present_with_reason
      btn.sensitive = present
      btn.tooltip_text = present ? 'Take a Picture…' : reason
    end
  end

  def scroller
    @scroller ||= Gtk::ScrolledWindow.new.tap do |sw|
      sw.hscrollbar_policy = :never
      sw.vexpand = true
    end
  end

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
      box.margin_top = 12
      box.margin_bottom = 12
      box.margin_start = 12
      box.margin_end = 12
    end
  end

  def thumbnail_grid
    @thumbnail_grid ||= Gtk::FlowBox.new.tap do |grid|
      grid.selection_mode = :single
      grid.homogeneous = true
      grid.min_children_per_line = 3
      grid.max_children_per_line = 5
      grid.row_spacing = 12
      grid.column_spacing = 12
      grid.valign = :start
    end
  end

  private

    def camera_present_with_reason
      [Ashpd::Camera.present?, 'No Camera Detected']
    rescue StandardError => e
      [false, "Camera portal unavailable: #{e.message}"]
    end

  # Each stock avatar is rendered to a PNG once, so choosing one produces the
  # same kind of Avatar as choosing a file does.
    def thumbnail_for(icon_name)
      Gtk::FlowBoxChild.new.tap do |child|
        child.add_css_class('card')
        child.child = Gtk::Image.new.tap do |image|
          image.icon_name = icon_name
          image.pixel_size = ICON_SIZE
          image.margin_top = 12
          image.margin_bottom = 12
        end

        child.define_singleton_method(:avatar_data) { AvatarSelector.render_icon(icon_name) }
      end
    end

  # Paints a symbolic icon onto a square surface and encodes it as PNG, so a
  # stock avatar is stored exactly like a photograph the user picked.
  #
  # The route through Gtk::Snapshot -> Gsk::RenderNode#draw is the one that
  # works in these bindings: Gtk::IconPaintable#file is nil for icons that
  # live in a gresource, so there is no image file to load, and turning a
  # paintable into a Gdk::Texture would need a Gsk renderer.
    def self.render_icon(icon_name)
      icon_node(icon_name).then do |node|
        Cairo::ImageSurface.new(:argb32, Avatar::STORED_SIZE, Avatar::STORED_SIZE).then do |surface|
          Cairo::Context.new(surface).tap do |cr|
            cr.set_source_rgb(0.87, 0.87, 0.89)
            cr.paint
            cr.translate(Avatar::STORED_SIZE / 4.0, Avatar::STORED_SIZE / 4.0)
            node&.draw(cr)
          end
          StringIO.new.tap { |io| surface.write_to_png(io) }.string
        end
      end.then { |png| Avatar.new(data: png, media_type: 'image/png') }
    rescue StandardError, GLib::Error => e
      warn "Could not render avatar #{icon_name}: #{e.message}"
      nil
    end

    def self.icon_node(icon_name)
      (Avatar::STORED_SIZE / 2).then do |size|
        Gtk::IconTheme.get_for_display(Gdk::Display.default).lookup_icon(icon_name, size).then do |paintable|
          Gtk::Snapshot.new.then do |snapshot|
            paintable.snapshot(snapshot, size, size)
            snapshot.to_node
          end
        end
      end
    end

    def choose_file
      Gtk::FileDialog.new.tap do |dialog|
        dialog.title = 'Choose Avatar'
        dialog.filters = image_filters
        dialog.open(root, nil) do |_, result|
          open_cropper(dialog.open_finish(result))
        rescue GLib::Error => e
          warn "Avatar selection cancelled: #{e.message}"
        end
      end
    end

    def image_filters
      Gio::ListStore.new(Gtk::FileFilter).tap do |filters|
        filters.append(
          Gtk::FileFilter.new.tap do |filter|
                  filter.name = 'Images'
                  filter.add_mime_type('image/*')
                end,
        )
      end
    end

    def open_cropper(file)
      file.then do |target|
        if target
          GdkPixbuf::Pixbuf.new(file: target.path).then do |pixbuf|
            CropDialog.new(pixbuf, ->(avatar) { select(avatar) }).tap do |cropper|
              cropper.build
              cropper.present(root)
            end
          end
        end
      end
    rescue StandardError, GLib::Error => e
      warn "Could not load image: #{e.message}"
      report_failure
    end

  # Upstream's avatar selector shows this when the picked file cannot be turned
  # into an avatar; it has no heading, only the body.
    def report_failure
      @failure_dialog = Adwaita::AlertDialog.new(nil, 'Failed to set avatar.').tap do |dialog|
        dialog.add_response('close', '_Close')
        dialog.default_response = 'close'
        dialog.close_response = 'close'
        dialog.present(self)
      end
    end

  # The camera button is only ever sensitive once Ashpd::Camera.present? has
  # said yes, so reaching this means a camera was detected but the `ashpd`
  # gem has no call that opens it (see the class comment) — worth saying
  # outright rather than leaving the button do nothing.
    def report_no_capture
      @no_capture_dialog = Adwaita::AlertDialog.new(nil, "Camera capture isn't supported yet; choose a file instead.").tap do |dialog|
        dialog.add_response('close', '_Close')
        dialog.default_response = 'close'
        dialog.close_response = 'close'
        dialog.present(self)
      end
    end

    def select(avatar)
      @on_selected.call(avatar)
      close
    end
end
