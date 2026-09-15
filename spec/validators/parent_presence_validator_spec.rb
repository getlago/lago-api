# frozen_string_literal: true

require "rails_helper"

RSpec.describe ParentPresenceValidator do
  # A minimal record exposing two parent "foreign keys" and "associations".
  def record_class(**validator_options)
    Class.new do
      include ActiveModel::Model

      attr_accessor :left_id, :left, :right_id, :right

      def self.name = "ParentPresenceTestRecord"

      validates_with ParentPresenceValidator, **validator_options
    end
  end

  describe "exactly one (default)" do
    let(:klass) { record_class(parents: %i[left right], error: :exactly_one_required) }

    it "is valid with exactly one parent, through the foreign key or the association" do
      expect(klass.new(left_id: "x")).to be_valid
      expect(klass.new(right: Object.new)).to be_valid
    end

    it "rejects none" do
      record = klass.new

      expect(record).not_to be_valid
      expect(record.errors.details[:base]).to eq([{error: :exactly_one_required}])
    end

    it "rejects two" do
      record = klass.new(left_id: "x", right: Object.new)

      expect(record).not_to be_valid
      expect(record.errors.details[:base]).to eq([{error: :exactly_one_required}])
    end
  end

  describe "at most one (optional: true)" do
    let(:klass) { record_class(parents: %i[left right], optional: true, error: :single_required) }

    it "allows none or one" do
      expect(klass.new).to be_valid
      expect(klass.new(left_id: "x")).to be_valid
    end

    it "rejects two" do
      record = klass.new(left_id: "x", right_id: "y")

      expect(record).not_to be_valid
      expect(record.errors.details[:base]).to eq([{error: :single_required}])
    end
  end
end
