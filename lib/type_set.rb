# frozen_string_literal: true

# TypeSet is the list of type labels a field can carry, and the mapping
# between those labels and vCard TYPE parameters.
#
# Ported from upstream's src/core/contacts-type-set.vala,
# src/core/contacts-type-descriptor.vala and
# src/core/contacts-vcard-type-mapping.vala. Upstream keeps three sets —
# general, email and phone — because a phone can be a Pager or a TTY while an
# email cannot, and the editor shows a different dropdown for each.
#
# A descriptor is either a *vCard* descriptor (a label backed by one or more
# vCard TYPE parameters) or a *custom* one (a free-form label the user typed,
# stored as X-GOOGLE-LABEL like upstream does).
#
class TypeSet
  X_GOOGLE_LABEL = 'X-GOOGLE-LABEL'

  # The sentinel the dropdowns show last, which opens the custom-label entry.
  OTHER_LABEL = 'Other…'

  TypeDescriptor = Data.define(:display_name, :vcard_types, :custom) do
    def self.vcard(display_name, vcard_types) = new(display_name: display_name, vcard_types: vcard_types, custom: false)
    def self.custom_label(label) = new(display_name: label, vcard_types: [], custom: true)

    def custom? = custom
    def matches?(types) = !custom && !vcard_types.empty? && vcard_types.all? { |t| types.include?(t) }
  end

  attr_reader :category, :descriptors

  def initialize(category, mappings)
    @category = category
    @descriptors = mappings.map { |label, types| TypeDescriptor.vcard(label, types) }
  end

  # Labels for a Gtk::StringList, with the custom-label sentinel last.
  def labels = @descriptors.map(&:display_name) + [OTHER_LABEL]

  def default = @descriptors.first

  def find(display_name)
    @descriptors.find { |d| d.display_name == display_name } ||
      (display_name.to_s.empty? ? default : TypeDescriptor.custom_label(display_name))
  end

  def index_of(display_name) = @descriptors.index { |d| d.display_name == display_name }

  # Picks the descriptor best matching a set of vCard TYPE parameters.
  # Upstream lists the most specific mappings first and takes the first whose
  # types are all present, which is why "Work Fax" wins over plain "Work".
  def lookup_by_vcard_types(types)
    types.map(&:to_s).map(&:upcase).then do |upcased|
      @descriptors.find { |d| d.matches?(upcased) } || default
    end
  end

  # The vCard parameters to write for a label; a custom label round-trips
  # through X-GOOGLE-LABEL, exactly as upstream does.
  def vcard_parameters(display_name)
    find(display_name).then do |descriptor|
      if descriptor.custom?
        ["#{X_GOOGLE_LABEL}=#{descriptor.display_name}"]
      else
        descriptor.vcard_types.map { |type| "TYPE=#{type}" }
      end
    end
  end

  # Upstream's general_data: the fallback set, used for addresses and URLs.
  GENERAL = new('General', [['Home', %w[HOME]], ['Work', %w[WORK]]]).freeze

  EMAIL = new(
    'Emails',
    [
      ['Personal', %w[PERSONAL]],
                    ['Home', %w[HOME]],
                    ['Work', %w[WORK]]
    ],
  ).freeze

  # Ordered most-specific-first, as upstream requires for lookup to work.
  PHONE = new(
    'Phones',
    [
      ['Assistant', %w[X-EVOLUTION-ASSISTANT]],
                    ['Work Fax', %w[WORK FAX]],
                    ['Work', %w[WORK VOICE]],
                    ['Work', %w[WORK]],
                    ['Callback', %w[X-EVOLUTION-CALLBACK]],
                    ['Car', %w[CAR]],
                    ['Company', %w[X-EVOLUTION-COMPANY]],
                    ['Home Fax', %w[HOME FAX]],
                    ['Home', %w[HOME VOICE]],
                    ['Home', %w[HOME]],
                    ['ISDN', %w[ISDN]],
                    ['Mobile', %w[CELL]],
                    ['Other', %w[VOICE]],
                    ['Fax', %w[FAX]],
                    ['Pager', %w[PAGER]],
                    ['Radio', %w[X-EVOLUTION-RADIO]],
                    ['Telex', %w[X-EVOLUTION-TELEX]],
                    ['TTY', %w[X-EVOLUTION-TTYTDD]]
    ],
  ).freeze

  # Which set applies to which contact field.
  def self.for_field(field)
    case field
    when :emails then EMAIL
    when :phones then PHONE
    else GENERAL
    end
  end
end
