# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/errors/application_error'
require_relative '../../lib/validators/port_code_validator'

# Make sure we have the error class available for testing
module RouteFinder
  module Errors
    class ValidationError < ApplicationError; end unless defined?(ValidationError)
  end
end

RSpec.describe RouteFinder::Validators::PortCodeValidator do
  describe '.valid?' do
    context 'with valid port codes' do
      it 'returns true for standard port codes' do
        expect(described_class.valid?('CNSHA')).to be true
        expect(described_class.valid?('NLRTM')).to be true
        expect(described_class.valid?('ESBCN')).to be true
        expect(described_class.valid?('BRSSZ')).to be true
      end

      it 'returns true for port codes with allowed digits' do
        expect(described_class.valid?('AB234')).to be true
        expect(described_class.valid?('CD567')).to be true
        expect(described_class.valid?('EF289')).to be true
      end
    end

    context 'with invalid port codes' do
      it 'returns false for nil or empty inputs' do
        expect(described_class.valid?(nil)).to be false
        expect(described_class.valid?('')).to be false
      end

      it 'returns false for codes that are too short' do
        expect(described_class.valid?('CNS')).to be false
        expect(described_class.valid?('ABC')).to be false
      end

      it 'returns false for codes that are too long' do
        expect(described_class.valid?('CNSHAA')).to be false
        expect(described_class.valid?('ABCDEF')).to be false
      end

      it 'returns false for codes with lowercase letters' do
        expect(described_class.valid?('cnsha')).to be false
        expect(described_class.valid?('CNsha')).to be false
      end

      it 'returns false for codes with forbidden digits (0 and 1)' do
        expect(described_class.valid?('AB01C')).to be false
        expect(described_class.valid?('CD10E')).to be false
      end

      it 'returns false for codes with special characters' do
        expect(described_class.valid?('AB-CD')).to be false
        expect(described_class.valid?('XY@Z2')).to be false
      end
    end
  end

  describe '.validate!' do
    context 'with valid port codes' do
      it 'does not raise an error' do
        expect { described_class.validate!('CNSHA') }.not_to raise_error
        expect { described_class.validate!('NLRTM', 'destination') }.not_to raise_error
      end
    end

    context 'with invalid port codes' do
      it 'raises ValidationError for nil or empty inputs' do
        expect { described_class.validate!(nil) }
          .to raise_error(RouteFinder::Errors::ValidationError, /cannot be nil or empty/)
        expect { described_class.validate!('') }
          .to raise_error(RouteFinder::Errors::ValidationError, /cannot be nil or empty/)
      end

      it 'raises ValidationError for invalid format' do
        expect { described_class.validate!('ABC12') }
          .to raise_error(RouteFinder::Errors::ValidationError, /Invalid.*format/)
        expect { described_class.validate!('AB01C') }
          .to raise_error(RouteFinder::Errors::ValidationError, /Invalid.*format/)
      end

      it 'includes the port type in the error message' do
        expect { described_class.validate!('ABC12', 'origin') }
          .to raise_error(RouteFinder::Errors::ValidationError, /Invalid origin port code format/)
        expect { described_class.validate!('AB01C', 'destination') }
          .to raise_error(RouteFinder::Errors::ValidationError, /Invalid destination port code format/)
      end
    end
  end

  describe '.format_description' do
    it 'returns a descriptive string of the expected format' do
      expect(described_class.format_description).to be_a(String)
      expect(described_class.format_description).to include('2 uppercase letters')
      expect(described_class.format_description).to include('no 0 or 1')
    end
  end
end
