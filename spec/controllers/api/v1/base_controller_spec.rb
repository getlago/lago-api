# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::BaseController do
  describe "v1 controllers" do
    subject(:controller_classes) do
      paths.map do |path|
        relative = Pathname(path).relative_path_from(controllers_root).sub_ext("")
        relative.each_filename.map { |segment| inflector.camelize(segment, path) }.join("::").constantize
      end
    end

    let(:controllers_root) { Rails.root.join("app/controllers") }
    let(:inflector) { Rails.autoloaders.main.inflector }
    let(:paths) do
      Dir[controllers_root.join("api/v1/**/*_controller.rb")] - [controllers_root.join("api/v1/base_controller.rb").to_s]
    end

    it "inherit from it" do
      expect(controller_classes).not_to be_empty
      expect(controller_classes.reject { it < described_class }).to eq([])
    end
  end

  describe ".max_page_size" do
    subject(:max_page_size) { described_class.max_page_size }

    it { expect(max_page_size).to be_nil }
  end

  describe "callbacks" do
    subject(:filters) { described_class._process_action_callbacks.map(&:filter) }

    it { expect(filters).to include(:validate_pagination_params) }
  end

  [Api::BaseController, Api::V2::BaseController].each do |klass|
    describe klass.name do
      subject(:controller_class) { klass }

      it "does not check the v1 page size" do
        expect(controller_class._process_action_callbacks.map(&:filter)).not_to include(:validate_pagination_params)
        expect(controller_class.private_method_defined?(:validate_pagination_params)).to be(false)
        expect(controller_class.respond_to?(:max_page_size)).to be(false)
      end
    end
  end
end
