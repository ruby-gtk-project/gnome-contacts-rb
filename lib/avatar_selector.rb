# frozen_string_literal: true

require 'adwaita'
require 'stringio'
require_relative 'crop_dialog'

# AvatarSelector offers a grid of stock avatars plus a "choose a file" button.
#
# Ported from upstream's src/contacts-avatar-selector.vala. Upstream also
# offers a camera source through the XDG desktop portal; there is no portal
# binding in ruby-gnome, so that button is not present — a file chosen here is
# handed to CropDialog exactly as upstream does.
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
          hb.pack_end(remove_button)

          file_button.signal_connect('clicked') { choose_file }
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
      filters.append(Gtk::FileFilter.new.tap do |filter|
        filter.name = 'Images'
        filter.add_mime_type('image/*')
      end)
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
  end

  def select(avatar)
    @on_selected.call(avatar)
    close
  end
end
