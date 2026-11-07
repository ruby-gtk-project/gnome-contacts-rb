# frozen_string_literal: true

require 'fileutils'

# DontSuggestStore is a port of the `dont_suggest_link` map and the
# `read_dont_suggest_db` / `write_dont_suggest_db` / `may_suggest_link` /
# `add_no_suggest_link` methods on upstream's src/contacts-store.vala.
#
# Upstream keeps a Gee::HashMultiMap<string, string> of persona-uid pairs the
# user has told it never to suggest linking again, persisted one "id1 id2"
# pair per line to ~/.config/gnome-contacts/dont_suggest.db (read back on
# construction, rewritten after every dismissal). This port has no persona
# layer — one Contact per entry, not personas linked under an Individual — so
# a Contact's own id stands in for the persona uid pairs upstream stores.
#
# Following lib/settings.rb's convention, the directory is "ruby-contacts"
# rather than upstream's "gnome-contacts", so this port's state never
# collides with a real GNOME Contacts install on the same machine.
class DontSuggestStore
  def initialize(path: nil)
    @path = path || default_path
    @pairs = read_dont_suggest_db
  end

  def location = @path

  # Mirrors upstream's `may_suggest_link`: false once either direction of the
  # (a, b) pair has been recorded as dismissed.
  def may_suggest_link?(id_a, id_b)
    !@pairs.include?([id_a, id_b]) && !@pairs.include?([id_b, id_a])
  end

  # Mirrors upstream's `add_no_suggest_link`: records the pair (in the order
  # given, as upstream does with persona1/persona2) and rewrites the db file.
  def add_no_suggest_link(id_a, id_b)
    pair = [id_a, id_b]
    unless @pairs.include?(pair)
      @pairs << pair
      write_dont_suggest_db
    end
  end

  private

    def default_path
      File.join(
        ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')),
        'ruby-contacts',
        'dont_suggest.db',
      )
    end

  # One "id1 id2" pair per line, exactly as upstream's write_dont_suggest_db
  # formats it (`"%s %s\n" % [key, value]`).
    def read_dont_suggest_db
      if File.exist?(@path)
        File.readlines(@path, chomp: true).filter_map do |line|
          ids = line.split(' ')
          if ids.length == 2
            [ids[0], ids[1]]
          end
        end
      else
        []
      end
    rescue Errno::ENOENT
      []
    end

    def write_dont_suggest_db
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, @pairs.map { |a, b| "#{a} #{b}\n" }.join)
    end
end
