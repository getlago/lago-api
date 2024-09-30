# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModelFactory, type: :service do
  subject(:factory) { described_class }

  let(:charge) { build(:standard_charge) }
  let(:aggregation_result) { BaseService::Result.new }
  let(:properties) { charge.properties }

  let(:result) { factory.new_instance(charge:, aggregation_result:, properties:) }

  describe '#new_instance' do
    context 'with standard charge model' do
      it { expect(result).to be_a(Charges::ChargeModels::StandardService) }

      context 'when charge is grouped' do
        let(:charge) { build(:standard_charge, properties: {grouped_by: ['cloud']}) }
        let(:aggregation_result) { BaseService::Result.new.tap { |r| r.aggregations = [BaseService::Result.new] } }

        it { expect(result).to be_a(Charges::ChargeModels::GroupedService) }
      end
    end

    context 'with graduated charge model' do
      let(:charge) { build(:graduated_charge) }

      it { expect(result).to be_a(Charges::ChargeModels::GraduatedService) }

      context 'when charge is prorated' do
        let(:charge) { build(:graduated_charge, prorated: true) }

        it { expect(result).to be_a(Charges::ChargeModels::ProratedGraduatedService) }
      end
    end

    context 'with graduated_percentage charge model' do
      let(:charge) { build(:graduated_percentage_charge) }

      it { expect(result).to be_a(Charges::ChargeModels::GraduatedPercentageService) }
    end

    context 'with package charge model' do
      let(:charge) { build(:package_charge) }

      it { expect(result).to be_a(Charges::ChargeModels::PackageService) }
    end

    context 'with percentage charge model' do
      let(:charge) { build(:percentage_charge) }

      it { expect(result).to be_a(Charges::ChargeModels::PercentageService) }
    end

    context 'with volume charge model' do
      let(:charge) { build(:volume_charge) }

      it { expect(result).to be_a(Charges::ChargeModels::VolumeService) }
    end

    context 'with dynamic charge model' do
      let(:charge) { build(:dynamic_charge) }

      it { expect(result).to be_a(Charges::ChargeModels::DynamicService) }
    end

    context 'with custom charge model' do
      let(:charge) { build(:custom_charge) }

      it { expect(result).to be_a(Charges::ChargeModels::CustomService) }
    end
  end
end
