# frozen_string_literal: true

class BillableMetricInput < BaseLegacyInput
  def create_input
    if args[:group].present? && args[:filters].blank?
      return args unless group_args[:key].present? && group_args[:values].present?

      if one_dimension?
        args[:filters] = [
          {
            key: group_args[:key],
            values: group_args[:values],
          },
        ]
      else
        args[:filters] = [
          {
            key: group_args[:key],
            values: group_args[:values].map { |v| v[:name] },
          },
        ]

        group_args[:values].each do |group|
          existing_result = args[:filters].find { |r| r[:key] == group[:key] }

          if existing_result
            existing_result[:values] = (existing_result[:values] + group[:values]).uniq
          else
            args[:filters] << {
              key: group[:key],
              values: group[:values],
            }
          end
        end
      end
    elsif args[:filters].present?
      args[:group] = {}
    end

    args
  end

  alias update_input create_input

  private

  def group_args
    @group_args ||= args[:group]
  end

  def one_dimension?
    # ie: { key: "region", values: ["USA", "EUROPE"] }
    group_args[:key].is_a?(String) && group_args[:values]&.all?(String)
  end
end
