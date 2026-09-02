# frozen_string_literal: true

require 'adwaita'

# SetupWindow is the first-run wizard asking which address book new contacts
# should go into.
#
# Ported from upstream's src/contacts-setup-window.vala and
# data/ui/contacts-setup-window.blp: a status page titled "Welcome" holding a
# clamped list of address books, with Quit and Done in the header bar. It is
# shown once, gated on the did-initial-setup setting.
#
class SetupWindow
  def initialize(app, backends, on_done)
    @app = app
    @backends = backends
    @on_done = on_done
    @selected = backends.first
  end

  def build
    window.tap do |win|
      win.content = toolbar_view

      toolbar_view.tap do |tv|
        tv.add_top_bar(header_bar)
        tv.content = status_page

        header_bar.tap do |hb|
          # Adwaita::HeaderBar has no show_title_buttons; the two ends are
          # controlled separately.
          hb.show_start_title_buttons = false
          hb.show_end_title_buttons = false
          hb.pack_start(quit_button)
          hb.pack_end(done_button)

          quit_button.signal_connect('clicked') { @app.quit }
          done_button.signal_connect('clicked') { finish }
        end

        status_page.tap do |page|
          page.child = clamp

          clamp.tap do |c|
            c.child = address_book_list

            address_book_list.tap do |list|
              @backends.each { |backend| list.add(address_book_row(backend)) }
            end
          end
        end
      end

      done_button.sensitive = !@selected.nil?
    end
  end

  def present = window.present

  # Memoized widget methods

  def window
    @window ||= Adwaita::ApplicationWindow.new(@app).tap do |win|
      win.title = 'Contacts Setup'
      win.set_default_size(800, 600)
      win.set_size_request(360, 400)
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def quit_button
    @quit_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Quit'
      btn.use_underline = true
      btn.tooltip_text = 'Cancel Setup And Quit'
      btn.can_shrink = true
    end
  end

  def done_button
    @done_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Done'
      btn.use_underline = true
      btn.tooltip_text = 'Complete setup'
      btn.can_shrink = true
      btn.add_css_class('suggested-action')
    end
  end

  def status_page
    @status_page ||= Adwaita::StatusPage.new.tap do |page|
      page.title = 'Welcome'
      page.icon_name = 'address-book-new-symbolic'
      page.description = 'Please select your main address book: this is where new contacts ' \
                         'will be added.'
    end
  end

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |c|
      c.maximum_size = 420
    end
  end

  def address_book_list
    @address_book_list ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Address Books'
    end
  end

  private

  # One selectable row per available backend; the radio buttons share a group
  # so exactly one is ever active.
    def address_book_row(backend)
      Adwaita::ActionRow.new.tap do |row|
        row.title = backend.display_name
        row.subtitle = backend.location
        row.activatable = true

        selection_button(backend).tap do |button|
          row.add_prefix(button)
          row.activatable_widget = button
        end
      end
    end

    def selection_button(backend)
      Gtk::CheckButton.new.tap do |button|
        button.valign = :center
        if @first_button
          button.group = @first_button
        end
        button.active = backend.equal?(@selected)
        @first_button ||= button

        button.signal_connect('toggled') do
          if button.active?
            @selected = backend
          end
          done_button.sensitive = !@selected.nil?
        end
      end
    end

  # The window is closed rather than destroyed, and the callback runs first:
  # the caller defers its own work to an idle tick, so by the time the window
  # goes away nothing is still reading from it.
    def finish
      @on_done.call(@selected)
      window.close
    end
end
