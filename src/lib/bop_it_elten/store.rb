# encoding: utf-8
# frozen_string_literal: true

module BopItElten
  # Engine <-> persistence bridge. The engine reads/writes (section, key)
  # string pairs (sections "bopit" and "passit", keys "hs0".."hs2") through
  # this store, which keeps them in one JSON file in the program's data
  # directory. read_json/write_json are Program's own monitored helpers, so
  # concurrent reads/writes from Elten are safe.
  class Store
    FILE = 'highscores.json'

    def initialize(program)
      @program = program
    end

    def read(section, key)
      data = @program.read_json(FILE, default: {})
      return '' unless data.is_a?(Hash)

      group = data[section]
      return '' unless group.is_a?(Hash)

      value = group[key]
      value.nil? ? '' : value.to_s
    end

    def write(section, key, value)
      data = @program.read_json(FILE, default: {})
      data = {} unless data.is_a?(Hash)
      group = data[section]
      unless group.is_a?(Hash)
        group = {}
        data[section] = group
      end
      group[key] = value.to_s
      @program.write_json(FILE, data)
    end
  end
end
