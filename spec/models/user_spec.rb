# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  subject { described_class.new(email: "gavin@hooli.com", password: "f**k_piedpiper") }

  it_behaves_like "paper_trail traceable"

  describe "Validations" do
    it "is valid with valid attributes" do
      expect(subject).to be_valid
    end

    it "is not valid with no email" do
      subject.email = nil
      expect(subject).not_to be_valid
    end

    it "is not valid with no password" do
      subject.password = nil
      expect(subject).not_to be_valid
    end
  end
end
