# frozen_string_literal: true

require 'gtk4'
require_relative 'contact_store'

# ShellSearchProvider exposes contacts to the GNOME Shell overview search.
#
# Ported from upstream's src/contacts-shell-search-provider.vala plus the two
# data files that register it (org.gnome.Contacts.search-provider.ini and the
# D-Bus .service). It implements org.gnome.Shell.SearchProvider2:
#
#   GetInitialResultSet(as)   -> as    ids matching the terms
#   GetSubsearchResultSet(as, as) -> as  same, narrowed
#   GetResultMetas(as)        -> aa{sv} id/name/description per result
#   ActivateResult(s, as, u)         open that contact
#   LaunchSearch(as, u)              open the app with the search filled in
#
# The search itself reuses ContactStore's filter, so the overview and the
# in-app search agree on what matches.
#
class ShellSearchProvider
  INTERFACE = 'org.gnome.Shell.SearchProvider2'
  OBJECT_PATH = '/org/gnome/Contacts/SearchProvider'
  MAX_RESULTS = 20

  NODE_XML = <<~XML
    <node>
      <interface name="org.gnome.Shell.SearchProvider2">
        <method name="GetInitialResultSet">
          <arg type="as" name="terms" direction="in"/>
          <arg type="as" name="results" direction="out"/>
        </method>
        <method name="GetSubsearchResultSet">
          <arg type="as" name="previous_results" direction="in"/>
          <arg type="as" name="terms" direction="in"/>
          <arg type="as" name="results" direction="out"/>
        </method>
        <method name="GetResultMetas">
          <arg type="as" name="identifiers" direction="in"/>
          <arg type="aa{sv}" name="metas" direction="out"/>
        </method>
        <method name="ActivateResult">
          <arg type="s" name="identifier" direction="in"/>
          <arg type="as" name="terms" direction="in"/>
          <arg type="u" name="timestamp" direction="in"/>
        </method>
        <method name="LaunchSearch">
          <arg type="as" name="terms" direction="in"/>
          <arg type="u" name="timestamp" direction="in"/>
        </method>
      </interface>
    </node>
  XML

  def initialize(store, on_activate: nil, on_launch: nil)
    @store = store
    @on_activate = on_activate
    @on_launch = on_launch
  end

  # Registers the provider on the connection the application already owns, the
  # way upstream does from Application.dbus_register.
  #
  # Note lookup_interface rather than interfaces.first: Gio::DBusNodeInfo
  # #interfaces returns unusable strings in these bindings, while
  # #lookup_interface returns the Gio::DBusInterfaceInfo that is wanted here.
  def register(connection)
    interface_info.then do |interface|
      connection.register_object(OBJECT_PATH, interface, method(:handle_method_call))
    end
  rescue StandardError, GLib::Error => e
    warn "Could not register the search provider: #{e.message}"
    nil
  end

  def interface_info = Gio::DBusNodeInfo.new(NODE_XML).lookup_interface(INTERFACE)

  # --- Interface methods ---------------------------------------------------

  # GNOME Shell splits the typed query into terms; a contact matches when it
  # matches every one of them, which is what makes "ada lov" find Ada Lovelace.
  def initial_result_set(terms)
    normalized(terms).then do |needles|
      needles.empty? ? [] : matching(needles).first(MAX_RESULTS).map(&:id)
    end
  end

  def subsearch_result_set(previous_results, terms)
    normalized(terms).then do |needles|
      contacts_by_id(previous_results).select { |contact| matches_all?(contact, needles) }
                                      .first(MAX_RESULTS).map(&:id)
    end
  end

  def result_metas(ids)
    contacts_by_id(ids).map { |contact| meta_for(contact) }
  end

  def activate_result(id, _terms, _timestamp) = @on_activate&.call(id)
  def launch_search(terms, _timestamp) = @on_launch&.call(terms.join(' '))

  private

    def handle_method_call(_connection, _sender, _path, _interface, method_name, parameters, invocation)
      case method_name
      when 'GetInitialResultSet'
        invocation.return_value(string_array(initial_result_set(parameters.get_child_value(0).to_a)))
      when 'GetSubsearchResultSet'
        invocation.return_value(
          string_array(
            subsearch_result_set(
              parameters.get_child_value(0).to_a,
              parameters.get_child_value(1).to_a,
            ),
          ),
        )
      when 'GetResultMetas'
        invocation.return_value(metas_variant(result_metas(parameters.get_child_value(0).to_a)))
      when 'ActivateResult'
        activate_result(parameters.get_child_value(0).get_string, [], 0)
        invocation.return_value(nil)
      when 'LaunchSearch'
        launch_search(parameters.get_child_value(0).to_a, 0)
        invocation.return_value(nil)
      else
        invocation.return_dbus_error("#{INTERFACE}.UnknownMethod", "Unknown method #{method_name}")
      end
    rescue StandardError => e
      invocation.return_dbus_error("#{INTERFACE}.Error", e.message)
    end

    def normalized(terms) = Array(terms).map { |t| t.to_s.downcase.strip }.reject(&:empty?)

    def matching(needles)
      @store.contacts.select { |contact| matches_all?(contact, needles) }
    end

  # Every term must appear somewhere in the contact, matching the in-app search.
    def matches_all?(contact, needles)
      haystack(contact).then { |text| needles.all? { |needle| text.include?(needle) } }
    end

    def haystack(contact)
      @store.send(:searchable_fields, contact).join(' ').downcase
    end

    def contacts_by_id(ids)
      @store.contacts.each_with_object({}) { |c, by_id| by_id[c.id] = c }
            .then { |by_id| Array(ids).filter_map { |id| by_id[id.to_s] } }
    end

  # The shell renders these: an id, a name and a one-line description.
    def meta_for(contact)
      {
        'id'          => contact.id.to_s,
        'name'        => contact.display_name,
        'description' => description_for(contact),
      }
    end

    def description_for(contact)
      [contact.role_display, contact.emails.first&.value, contact.phones.first&.value]
        .map(&:to_s).find { |v| !v.strip.empty? }.to_s
    end

  # Reply variants are built by parsing GVariant text.
  #
  # GLib::Variant.new cannot construct a dictionary in these bindings — it
  # raises NotImplementedError for a{sv} — and it cannot build the tuple a
  # D-Bus reply needs either. GLib::Variant.parse(text, type) handles both.
    def string_array(values)
      GLib::Variant.parse("([#{values.map { |v| quote(v) }.join(', ')}],)", '(as)')
    end

    def metas_variant(metas)
      GLib::Variant.parse("(#{metas_text(metas)},)", '(aa{sv})')
    end

    def metas_text(metas)
      "[#{metas.map { |meta| meta_text(meta) }.join(', ')}]"
    end

    def meta_text(meta)
      "{#{meta.map { |key, value| "#{quote(key)}: <#{quote(value)}>" }.join(', ')}}"
    end

  # GVariant text format uses the same string escapes as C. The block form of
  # gsub is deliberate: backslashes in a replacement string are themselves
  # interpreted, which makes the escaping of an escape character unreadable.
    ESCAPES = { '\\' => '\\\\', '"' => '\\"' }.freeze

    def quote(value) = %("#{value.to_s.gsub(/[\\"]/) { |char| ESCAPES.fetch(char) }}")
end
