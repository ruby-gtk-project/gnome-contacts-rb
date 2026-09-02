# frozen_string_literal: true

require_relative 'test_helper'
require 'type_set'

class TestTypeSet < Minitest::Test
  def test_each_field_gets_its_own_set
    assert_equal TypeSet::EMAIL, TypeSet.for_field(:emails)
    assert_equal TypeSet::PHONE, TypeSet.for_field(:phones)
    assert_equal TypeSet::GENERAL, TypeSet.for_field(:addresses)
    assert_equal TypeSet::GENERAL, TypeSet.for_field(:urls)
  end

  def test_email_labels_match_upstream
    assert_equal ['Personal', 'Home', 'Work', TypeSet::OTHER_LABEL], TypeSet::EMAIL.labels
  end

  def test_phone_set_carries_the_long_upstream_list
    TypeSet::PHONE.descriptors.map(&:display_name).then do |labels|
      ['Mobile', 'Work Fax', 'Home Fax', 'Pager', 'TTY', 'ISDN', 'Car', 'Telex'].each do |expected|
        assert_includes labels, expected
      end
    end
  end

  # Upstream lists the most specific mappings first and takes the first whose
  # types are all present, so WORK+FAX must not resolve to plain Work.
  def test_lookup_prefers_the_most_specific_mapping
    assert_equal 'Work Fax', TypeSet::PHONE.lookup_by_vcard_types(%w[WORK FAX]).display_name
    assert_equal 'Work', TypeSet::PHONE.lookup_by_vcard_types(%w[WORK]).display_name
    assert_equal 'Mobile', TypeSet::PHONE.lookup_by_vcard_types(%w[CELL]).display_name
    assert_equal 'Home Fax', TypeSet::PHONE.lookup_by_vcard_types(%w[FAX HOME]).display_name
  end

  def test_lookup_is_case_insensitive_and_falls_back_to_the_default
    assert_equal 'Work', TypeSet::PHONE.lookup_by_vcard_types(%w[work]).display_name
    assert_equal TypeSet::PHONE.default, TypeSet::PHONE.lookup_by_vcard_types(%w[NONSENSE])
  end

  def test_known_labels_map_back_to_vcard_types
    assert_equal ['TYPE=WORK', 'TYPE=FAX'], TypeSet::PHONE.vcard_parameters('Work Fax')
    assert_equal ['TYPE=CELL'], TypeSet::PHONE.vcard_parameters('Mobile')
  end

  # A label the user typed is not a vCard TYPE, so it round-trips through
  # X-GOOGLE-LABEL, which is what upstream does.
  def test_custom_labels_use_the_google_label_parameter
    assert_equal ['X-GOOGLE-LABEL=My Boat'], TypeSet::PHONE.vcard_parameters('My Boat')
    assert_predicate TypeSet::PHONE.find('My Boat'), :custom?
    refute_predicate TypeSet::PHONE.find('Mobile'), :custom?
  end

  def test_index_of_is_nil_for_a_custom_label
    assert_equal 0, TypeSet::EMAIL.index_of('Personal')
    assert_nil TypeSet::EMAIL.index_of('My Boat')
  end
end
