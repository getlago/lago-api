# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 native controllers" do # rubocop:disable RSpec/DescribeClass
  # The controllers the native v2 routes reach, nested ones included, with their routed actions.
  # The v1 controllers that serve the rest of /api/v2 are left out.
  native_actions = Rails.application.routes.routes
    .map(&:defaults)
    .select { it[:controller]&.start_with?("api/v2/") }
    .group_by { "#{it[:controller]}_controller".camelize.constantize }
    .transform_values { |defaults| defaults.map { it[:action] }.uniq }
  native_controllers = native_actions.keys

  hand_rendered_actions = {}

  # The Api::V1Errors renderers that the callers v1 and v2 share reach, which Api::V2Errors defines
  # under the same names, and the ones it must not define: render_error_response renders those
  # failures itself, and the v2 base controller rescues a missing parameter with its own handler.
  shared_renderers = %i[unauthorized_error forbidden_error validation_errors render_error_response]
  v1_only_renderers = %i[
    bad_request_error method_not_allowed_error provider_error thirdpary_error too_many_provider_requests_error
    lock_acquisition_error gone_error conflict_error
  ]
  v2_renderers = shared_renderers + %i[not_found_error not_found invalid_request_error]

  let(:base_callbacks) { before_callbacks(Api::V2::BaseController) }

  def before_callbacks(controller)
    controller._process_action_callbacks.select { it.kind == :before }.map(&:filter)
  end

  # A floor, so that a change to the route filter cannot empty the list unnoticed.
  it "walks every native controller" do
    expect(native_controllers.size).to be >= 11
  end

  # A renderer added to Api::V1Errors later fails here until it is classified.
  it "classifies every Api::V1Errors renderer as shared or v1 only" do
    expect(Api::V1Errors.public_instance_methods(false)).to match_array(shared_renderers + v1_only_renderers)
  end

  native_controllers.each do |native_controller|
    context "with #{native_controller.name}" do
      subject(:callbacks) { before_callbacks(native_controller) }

      it "inherits the base controller and its expand validation" do
        expect(native_controller).to be < Api::V2::BaseController
        expect(native_controller).to be < Api::Serializable
      end

      it "renders its errors with Api::V2Errors" do
        expect(native_controller).to be < Api::V2Errors
        expect(native_controller.ancestors).not_to include(Api::V1Errors)
        expect(v2_renderers.index_with { native_controller.instance_method(it).owner }).to eq(v2_renderers.index_with(Api::V2Errors))
        expect(v1_only_renderers.select { native_controller.method_defined?(it) || native_controller.private_method_defined?(it) }).to be_empty
      end

      if (native_actions[native_controller] - hand_rendered_actions.fetch(native_controller, [])).any?
        it "declares what it renders with serializable_with" do
          expect(native_controller.new.send(:serialization)).to be_present
        end
      end

      it "validates expand after the catalog check and before the cursor" do
        expect(callbacks & %i[ensure_product_catalog! validate_expand! read_cursor])
          .to eq(%i[ensure_product_catalog! validate_expand! read_cursor])
      end

      it "validates expand before every callback of its own" do
        expect(callbacks.take_while { it != :validate_expand! } - base_callbacks).to be_empty
      end
    end
  end
end
