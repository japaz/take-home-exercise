# frozen_string_literal: true

module RouteFinder
  module Errors
    # Base class for all application errors
    class ApplicationError < StandardError; end

    # Error raised when a file is not found
    class FileNotFoundError < ApplicationError; end

    # Error raised when data format is invalid
    class InvalidDataError < ApplicationError; end

    # Error raised when required data is missing
    class MissingDataError < ApplicationError; end

    # Error raised when currency conversion fails
    class CurrencyConversionError < ApplicationError; end

    # Error raised when an invalid route is specified
    class InvalidRouteError < ApplicationError; end

    # Error raised when validation fails
    class ValidationError < ApplicationError; end

    # Error raised when calculations fail
    class CalculationError < ApplicationError; end
  end
end
