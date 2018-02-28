# frozen_string_literal: true

require 'sinatra'
require 'json'

require_relative '../../lib/utils/class_factory'

module Helpers
  module ApiBuilder
    include Sequel
    include Sinatra
    include Utils::ClassFactory

    CONTENT_TYPE = 'application/json;charset=utf-8'

    def make_default_json_api(api_instance, payload = {}, table_name = nil)
      request_method = api_instance.env['REQUEST_METHOD']

      mapped_class, klass = verify_table(table_name)

      if payload.empty? && (%w[OPTIONS DELETE GET].index(request_method) != nil)

        begin
          api_instance.content_type CONTENT_TYPE
          status = 200
          my_yield = table_name.nil? ? yield : yield(mapped_class, klass)
          block_given? ? response = my_yield : response = { msg: 'Api not implemented yet.' }
        rescue ModelException => e
          status = 400
          response = prepare_error_response(e)
        end
        [status, response.to_json.delete("\n")]
      else

        begin
          api_instance.content_type CONTENT_TYPE
          body_params = prepare_payload(payload)
          status = 200

          if block_given?
            return_data = yield(body_params, status, mapped_class, klass)
            status = return_data[:status]
            response = return_data[:response]
          else
            response = { msg: 'Api not implemented yet.' }
          end
        rescue ModelException, ConstraintViolation, UniqueConstraintViolation, CheckConstraintViolation,
               NotNullConstraintViolation, ForeignKeyConstraintViolation, MassAssignmentRestriction, ValidationFailed => e
          status = 400
          response = prepare_error_response(e)
        end
        [status, response.to_json.delete("\n")]
      end
    end

    def prepare_payload(raw_payload)
      body_params = !raw_payload.empty? && !raw_payload.is_a?(IndifferentHash) && raw_payload.length >= 2  \
      && raw_payload.match?(/\{*}/) ? ::MultiJson.decode(raw_payload, symbolize_keys: true) : raw_payload
      raise ModelException, 'Cannot parse Payload.' unless body_params
      body_params
    end

    def verify_table(table_name)
      unless table_name.nil?
        halt 403, { 'Content-Type' => 'application/json' }, ModelException.new("Forbidden access to: #{table_name}").to_json if table_name.eql?('configurations')
        mapped_class = App::ClassMap.detect { |map| map[:table_name] == table_name }
        halt 400, { 'Content-Type' => 'application/json' }, ModelException.new("Mapped class not found for name: #{table_name}").to_json unless mapped_class

        klass = class_from_string(mapped_class[:class_name])
        halt 400, { 'Content-Type' => 'application/json' }, ModelException.new("Class not found for name: #{mapped_class[:class_name]}").to_json unless klass
        [mapped_class, klass]
      end
    end

    def prepare_error_response(exception)
      exception.is_a?(ModelException) ? message = exception.message : message = exception.message[/DETAIL:(.*)/] || exception.to_s
      { error: { msg: message, status_code: 400 } }
    end
  end

  module ApiValidation
    # @param [Hash] body_params request body params
    # @param [Array] expected_params array of symbols of expected params
    def validate_params(body_params, expected_params)
      expected_params.each { |s| raise ModelException, "Parameter #{s} not found. Invalid payload." unless body_params.key?(s) }
    end
  end
end
