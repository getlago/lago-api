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

  # Every Api::V1Errors renderer, one added later included, so that the callers v1 and v2 share
  # always find a v2 one. The v2 base controller rescues a missing parameter with its own handler.
  v2_renderers = Api::V1Errors.public_instance_methods(false) - %i[bad_request_error] + %i[not_found_error invalid_request_error]

  let(:base_callbacks) { before_callbacks(Api::V2::BaseController) }

  def before_callbacks(controller)
    controller._process_action_callbacks.select { it.kind == :before }.map(&:filter)
  end

  # A floor, so that a change to the route filter cannot empty the list unnoticed.
  it "walks every native controller" do
    expect(native_controllers.size).to be >= 11
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
