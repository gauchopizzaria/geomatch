module Api
  module V1
    module Admin
      # GET /api/v1/admin/stats
      class StatsController < BaseController
        def show
          @stats = {
            total_users:      User.count,
            active_now:       User.where('last_seen_at > ?', 5.minutes.ago).count,
            new_today:        User.where('created_at > ?', Time.current.beginning_of_day).count,
            total_matches:    Match.count,
            messages_today:   Message.where('created_at > ?', Time.current.beginning_of_day).count,
            pending_reports:  Report.pending.count,
            banned_users:     User.where.not(banned_at: nil).count
          }
        end
      end
    end
  end
end
