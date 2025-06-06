# frozen_string_literal: true

module RouteFinder
  module Validators
    # Validation for port codes
    module PortCodeValidator
      # Port code format is 2 uppercase letters followed by 3 uppercase letters or digits (2-9 only, no 0 or 1)
      PORT_CODE_PATTERN = /^[A-Z]{2}[A-Z2-9]{3}$/

      # Validates that a port code follows the expected format
      def self.valid?(port_code)
        return false if port_code.nil? || port_code.empty?

        !!(port_code =~ PORT_CODE_PATTERN)
      end

      # Validates that a port code follows the expected format and raises an error if not
      def self.validate!(port_code, port_type = 'port')
        if port_code.nil? || port_code.empty?
          raise RouteFinder::Errors::ValidationError,
                "#{port_type.capitalize} port code cannot be nil or empty"
        end

        return if valid?(port_code)

        raise RouteFinder::Errors::ValidationError,
              "Invalid #{port_type.downcase} port code format: #{port_code}. " \
              'Expected format: 2 uppercase letters followed by 3 alphanumeric characters (e.g., CNSHA).'
      end

      # Description of the expected port code format for error messages
      def self.format_description
        '2 uppercase letters followed by 3 uppercase letters or digits (2-9 only, no 0 or 1)'
      end
    end
  end
end
