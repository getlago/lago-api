# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 native controllers" do # rubocop:disable RSpec/DescribeClass
  # The controllers the native v2 routes reach, nested ones included. The v1 controllers that
  # serve the rest of /api/v2 are left out.
  native_controllers = Rails.application.routes.routes
    .filter_map { it.defaults[:controller] }
    .select { it.start_with?("api/v2/") }
    .uniq
    .map { "#{it}_controller".camelize.constantize }

  let(:base_callbacks) { before_callbacks(Api::V2::BaseController) }

  def before_callbacks(controller)
    controller._process_action_callbacks.select { it.kind == :before }.map(&:filter)
  end

  it "walks every native controller" do
    expect(native_controllers.size).to eq(12)
  end

  native_controllers.each do |native_controller|
    context "with #{native_controller.name}" do
      subject(:callbacks) { before_callbacks(native_controller) }

      it "inherits the base controller and its expand validation" do
        expect(native_controller).to be < Api::V2::BaseController
        expect(native_controller).to be < Api::Expandable
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
