# frozen_string_literal: true

require_relative 'test_helper'
require 'vcard'

class TestVCard < Minitest::Test
  include TempData

  def test_dump_emits_a_well_formed_card
    VCard.dump(contact_hash).then do |text|
      assert_includes text, 'BEGIN:VCARD'
      assert_includes text, 'VERSION:4.0'
      assert_includes text, 'FN:Ada Lovelace'
      assert_includes text, 'N:Lovelace;Ada;;;'
      assert_includes text, 'EMAIL;TYPE=WORK:ada@analytical.engine'
      assert_includes text, 'BDAY:18151210'
      assert_includes text, 'CATEGORIES:Favourite'
      assert text.end_with?('END:VCARD')
    end
  end

  def test_round_trip_preserves_every_field
    VCard.parse_all(VCard.dump(contact_hash)).first.then do |parsed|
      assert_equal 'Ada Lovelace', parsed[:name]
      assert_equal 'Ada', parsed[:nickname]
      assert_equal ['ada@analytical.engine'], parsed[:emails].map { |e| e[:value] }
      assert_equal ['+44 20 7946 0100'], parsed[:phones].map { |p| p[:value] }
      assert_equal ['analytical.engine'], parsed[:urls].map { |u| u[:value] }
      assert_equal ['12 Marylebone Rd, London'], parsed[:addresses].map { |a| a[:value] }
      assert_equal 'Analytical Engine Co', parsed[:roles].first[:organization]
      assert_equal 'Mathematician', parsed[:roles].first[:title]
      assert_equal Date.new(1815, 12, 10), parsed[:birthday]
      assert parsed[:favorite]
    end
  end

  # Commas, semicolons and newlines are structural in vCard and must survive
  # escaping intact.
  def test_round_trip_preserves_special_characters
    "Likes; semicolons, commas\nand newlines".then do |tricky|
      VCard.parse_all(VCard.dump(contact_hash(notes: [{ value: tricky, type: 'personal' }]))).first.then do |parsed|
        assert_equal tricky, parsed[:notes].first[:value]
      end
    end
  end

  def test_long_values_are_folded_and_unfolded
    ('a' * 300).then do |long|
      VCard.dump(contact_hash(notes: [{ value: long, type: 'personal' }])).then do |text|
        assert text.lines.all? { |line| line.chomp.length <= 76 }, 'lines should be folded'
        assert_equal long, VCard.parse_all(text).first[:notes].first[:value]
      end
    end
  end

  def test_parse_all_reads_multiple_cards
    assert_equal 2, VCard.parse_all(VCard.dump_all([contact_hash, contact_hash(name: 'Grace Hopper')])).length
  end

  def test_parse_handles_foreign_cards
    VCard.parse_all(<<~VCF).first.then do |parsed|
      BEGIN:VCARD
      VERSION:3.0
      N:Hopper;Grace;;;
      item1.EMAIL;type=INTERNET;type=pref:grace@navy.mil
      TEL;TYPE="VOICE,WORK":+1 555 0100
      ADR;TYPE=WORK:;;1 Navy Yard;Washington;DC;20003;USA
      END:VCARD
    VCF
      assert_equal 'Grace Hopper', parsed[:name], 'should fall back to N when FN is absent'
      assert_equal 'grace@navy.mil', parsed[:emails].first[:value], 'should strip the item1. group prefix'
      assert_equal '+1 555 0100', parsed[:phones].first[:value]
      assert_equal '1 Navy Yard, Washington, DC, 20003, USA', parsed[:addresses].first[:value]
    end
  end

  def test_parse_ignores_empty_cards
    assert_empty VCard.parse_all("BEGIN:VCARD\r\nVERSION:4.0\r\nEND:VCARD\r\n")
  end

  def test_parse_accepts_typed_value_objects_from_the_model
    require 'contact'
    Contact.from_h(full_contact_attributes.merge(id: 'x')).then do |contact|
      assert_includes VCard.dump(contact.to_h), 'EMAIL;TYPE=WORK:ada@analytical.engine'
    end
  end

  private

  def contact_hash(**overrides)
    {
      id: 'ada-1',
      name: 'Ada Lovelace',
      nickname: 'Ada',
      birthday: Date.new(1815, 12, 10),
      favorite: true,
      emails: [{ value: 'ada@analytical.engine', type: 'work' }],
      phones: [{ value: '+44 20 7946 0100', type: 'home' }],
      urls: [{ value: 'analytical.engine', type: 'work' }],
      addresses: [{ value: '12 Marylebone Rd, London', type: 'home' }],
      notes: [],
      roles: [{ organization: 'Analytical Engine Co', title: 'Mathematician', type: 'work' }]
    }.merge(overrides)
  end
end
