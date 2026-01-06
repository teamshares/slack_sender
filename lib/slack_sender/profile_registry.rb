# frozen_string_literal: true

module SlackSender
  class ProfileNotFound < Error; end
  class DuplicateProfileError < Error; end

  class ProfileRegistry
    class << self
      def register(name, config)
        key = name.to_sym
        raise DuplicateProfileError, "Profile #{name} already registered" if all.key?(key)

        profile = Profile.new(**config)
        # Store the name on the profile instance for easy lookup
        profile.instance_variable_set(:@registered_name, key)
        all[key] = profile
        profile
      end

      def find(name)
        raise ProfileNotFound, "Profile name cannot be nil" if name.nil?
        raise ProfileNotFound, "Profile name cannot be empty" if name.to_s.strip.empty?

        all[name.to_sym] or raise ProfileNotFound, "Profile '#{name}' not found"
      end

      def all
        @profiles ||= {}
      end

      def clear!
        @profiles = {}
      end
    end
  end
end
