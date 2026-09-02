# frozen_string_literal: true

require 'adwaita'
require 'stringio'
require 'rqrcode_core'
require_relative 'vcard'

# QrCodeDialog renders a contact's vCard as a QR code so another device can
# scan it.
#
# Ported from upstream's src/contacts-qr-code-dialog.vala, which uses
# libqrencode. There is no libqrencode binding for Ruby, so the encoding comes
# from rqrcode_core (pure Ruby) and the modules are painted with Cairo, which
# is the same thing upstream does by hand with its pixel buffer.
#
class QrCodeDialog < Adwaita::Dialog
  IMAGE_SIZE = 300
  QUIET_ZONE = 4

  def initialize(contact)
    super()
    self.title = 'QR Code'
    self.content_width = 380
    self.content_height = 460
    @contact = contact
  end

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |tv|
        tv.add_top_bar(header_bar)
        tv.content = content_box

        content_box.tap do |box|
          box.append(qr_image)
          box.append(subtitle_label)

          qr_image.paintable = qr_texture
          subtitle_label.markup = "Scan the QR code to save the contact <b>#{escape(@contact.display_name)}</b>."
        end
      end
    end
  end

  # Memoized widget methods

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 18).tap do |box|
      box.halign = :center
      box.valign = :center
      box.margin_top = 24
      box.margin_bottom = 24
      box.margin_start = 24
      box.margin_end = 24
    end
  end

  def qr_image
    @qr_image ||= Gtk::Picture.new.tap do |picture|
      picture.set_size_request(IMAGE_SIZE, IMAGE_SIZE)
      picture.add_css_class('card')
    end
  end

  def subtitle_label
    @subtitle_label ||= Gtk::Label.new.tap do |label|
      label.wrap = true
      label.justify = :center
      label.max_width_chars = 32
    end
  end

  private

  # The QR payload is the contact's own vCard, exactly what exporting it gives.
    def vcard_text = "#{VCard.dump(@contact.to_h)}#{VCard::EOL}"

    def qr_texture
      RQRCodeCore::QRCode.new(vcard_text, level: :m, mode: :byte_8bit).then do |qr|
        Gdk::Texture.new(GLib::Bytes.new(render_png(qr)))
      end
    rescue StandardError, GLib::Error => e
      warn "Could not create QR code: #{e.message}"
      nil
    end

    def render_png(qr)
      (qr.module_count + (QUIET_ZONE * 2)).then do |total|
        [IMAGE_SIZE / total, 1].max.then do |pixel|
          Cairo::ImageSurface.new(:rgb24, total * pixel, total * pixel).then do |surface|
            Cairo::Context.new(surface).tap { |cr| paint_modules(cr, qr, pixel) }
            StringIO.new.tap { |io| surface.write_to_png(io) }.string
          end
        end
      end
    end

    def paint_modules(cairo, qr, pixel)
      cairo.set_source_rgb(1, 1, 1)
      cairo.paint
      cairo.set_source_rgb(0, 0, 0)

      qr.modules.each_with_index do |row, y|
        row.each_with_index do |dark, x|
          if dark
            cairo.rectangle(
              (x + QUIET_ZONE) * pixel,
              (y + QUIET_ZONE) * pixel,
              pixel,
              pixel,
            )
          end
        end
      end
      cairo.fill
    end

  # There is no GLib::Markup in these bindings, so escape the five characters
  # Pango markup treats specially.
    MARKUP_ESCAPES = { '&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', "'" => '&#39;' }.freeze

    def escape(text) = text.to_s.gsub(/[&<>"']/) { |char| MARKUP_ESCAPES.fetch(char) }
end
