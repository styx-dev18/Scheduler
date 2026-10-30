module Scheduling
  module StatusMachine
    STATUSES = %w[confirmed in_progress completed cancelled no_show].freeze
    TRANSITIONS = {
      "confirmed" => %w[in_progress cancelled no_show].freeze,
      "in_progress" => %w[completed].freeze,
      "completed" => [].freeze,
      "cancelled" => [].freeze,
      "no_show" => [].freeze
    }.freeze
    ACTIVE = %w[confirmed in_progress].freeze

    InvalidTransition = Class.new(StandardError)

    def self.allowed_from(status)
      TRANSITIONS.fetch(status.to_s, [])
    end

    def self.allowed?(from:, to:)
      allowed_from(from).include?(to.to_s)
    end

    def self.holds_resources?(status)
      ACTIVE.include?(status.to_s)
    end
  end
end
