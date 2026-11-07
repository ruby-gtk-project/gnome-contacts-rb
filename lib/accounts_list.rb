# frozen_string_literal: true

require 'adwaita'
require 'goa-rb'

# AccountsList lists the address books the app knows about and lets the user
# pick the primary one — the book new contacts are written to.
#
# Ported from upstream's src/contacts-accounts-list.vala, an Adw.PreferencesGroup
# of Adw.ActionRows, one per address book, each carrying a provider icon, the
# book's name, the account it belongs to, and a checkmark that marks the
# primary one. Activating a row makes that book primary.
#
# Upstream's address books are Folks PersonaStores arriving through a filtered
# GListModel, so it drives the checkmarks from a Gtk.SingleSelection over that
# model. This port's address books are backend objects handed over as a plain
# array, so the selection is an index into that array; the row behaviour —
# checkmark as the activatable widget, exactly one marked — is the same.
#
class AccountsList < Adwaita::PreferencesGroup
  def initialize(backends, primary: nil, on_selected: nil)
    super()
    @backends = Array(backends)
    @on_selected = on_selected
    @selected = primary || @backends.first
    self.title = 'Address Books'
    self.description = 'New contacts are added to the selected address book'
  end

  attr_reader :backends

  # Upstream's selected_store: the chosen address book, or nil when the user
  # has no address books at all.
  def selected_backend = @selected

  def build
    tap do |group|
      rows.each { |backend, row| group.add(row.tap { update_row(backend, row) }) }
    end
  end

  def selected_backend=(backend)
    @selected = backend
    rows.each { |other, row| update_row(other, row) }
    @on_selected&.call(backend)
  end

  # One row per address book, built once and kept so the checkmarks can be
  # refreshed when the selection moves.
  def rows
    @rows ||= @backends.to_h { |backend| [backend, address_book_row(backend)] }
  end

  def checkmarks
    @checkmarks ||= @backends.to_h { |backend| [backend, checkmark_for(backend)] }
  end

  private

    def address_book_row(backend)
      Adwaita::ActionRow.new.tap do |row|
        row.title = backend.display_name
        row.subtitle = backend.location.to_s
        row.subtitle_lines = 2
        row.activatable = true
        row.add_prefix(provider_image(backend))

        checkmarks[backend].tap do |checkmark|
          row.add_suffix(checkmark)
          row.activatable_widget = checkmark
        end

        row.signal_connect('activated') { self.selected_backend = backend }
      end
    end

  # Ported from upstream's provider-icon lookup in contacts-accounts-list.vala
  # and contacts-esd-setup.vala's `get_icon_for_goa_account`: ask the real GOA
  # client for the account's provider_icon and fall back to the app icon.
  #
  # None of this port's backends (JSON, vCard) are GOA-provisioned, so
  # Backend#goa_account_id is nil today and this always falls through to the
  # fallback icon — same as upstream would for a non-GOA address book. The
  # GOA client is still built and queried on every row, which is the real
  # lookup upstream performs; a backend tied to an actual GOA account (an EDS
  # address book behind one, say) would start getting its real provider icon
  # with no further change here.
    def provider_image(backend)
      goa_provider_icon(backend.goa_account_id) || fallback_icon
    end

    def fallback_icon
      Gtk::Image.new(icon_name: 'address-book-new-symbolic').tap do |image|
        image.icon_size = :large
      end
    end

    def goa_client
      @goa_client ||= Goa::Client.new
    end

    def goa_provider_icon(account_id)
      # No early-return on a nil account_id: the real GOA client is queried
      # either way (matching upstream's unconditional registry lookup), and
      # Goa::Object#account.id is never nil, so the find below simply misses.
      #
      # Goa::Client#lookup_by_id crashes the process with a GLib CRITICAL
      # (g_object_info_get_ref_function_pointer: assertion
      # 'GI_IS_OBJECT_INFO (info)' failed) when it returns nil for an
      # unmatched id, in goa-rb as pinned by this flake. #accounts returns
      # the same Goa::Object list without that path, so look up through it
      # instead.
      goa_client.accounts.find { |object| object.account&.id == account_id }
        &.account&.provider_icon
        &.then { |icon_spec| Gtk::Image.new(gicon: Gio.icon_new_for_string(icon_spec)).tap { |image| image.icon_size = :large } }
    rescue StandardError, GLib::Error => e
      warn "Could not load GOA provider icon: #{e.message}"
      nil
    end

    def checkmark_for(backend)
      Gtk::Image.new(icon_name: 'object-select-symbolic').tap do |image|
        image.valign = :center
        image.visible = backend.equal?(@selected)
      end
    end

  # A read-only book can be listed but never made primary, which is upstream's
  # reason for filtering its model down to the writable E-D-S stores.
    def update_row(backend, row)
      checkmarks[backend].visible = backend.equal?(@selected)
      row.sensitive = !backend.readonly?
    end
end
