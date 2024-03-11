# frozen_string_literal: true

module Utils
  class ChargeGroupTypeDeterminerService < BaseService
    def initialize(charge_group)
      @charge_group = charge_group
      super(nil)
    end

    def call
      result.charge_group_type = charge_group_type
    end

    private

    attr_reader :charge_group

    def charge_group_type
      return Constants::CHARGE_GROUP_TYPES[:PACKAGES_GROUP] if is_packages_group?
      return Constants::CHARGE_GROUP_TYPES[:PACKAGE_TIMEBASED_GROUP] if is_package_timebased_group?

      Constants::CHARGE_GROUP_TYPES[:UNKNOWN]
    end

    def is_package_timebased_group?
      has_exactly_two_charges? &&
        one_timebased_charge? &&
        one_package_group_charge?
    end

    def is_packages_group?
      has_exactly_two_charges? &&
        all_charges_are_package_group?
    end

    def has_exactly_two_charges?
      charge_group.charges.count == 2
    end

    def one_timebased_charge?
      charge_group.charges.timebased.count == 1
    end

    def one_package_group_charge?
      charge_group.charges.package_group.count == 1
    end

    def all_charges_are_package_group?
      charge_group.charges.package_group.count == 2
    end
  end
end
