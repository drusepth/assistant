module Kitchens
  # Which kitchen the Food hub opens on. Most people can see exactly one —
  # theirs, or the one a partner shared — and never meet this choice. For
  # the few who can see more (their own and a partner's, or the cabin), the
  # last one they picked wins, then the busiest.
  #
  # Nobody is left without one: a first visit makes "Home". That is created
  # rather than asked about because the kitchen is where the hub's first
  # useful action lands (add to the list), and an empty container shared
  # with nobody changes nothing for anybody else.
  class Current
    def self.for(user) = new(user).kitchen

    def initialize(user)
      @user = user
    end

    def kitchen
      chosen || busiest || @user.kitchens.create!(name: Kitchen::DEFAULT_NAME)
    end

    private
      def visible = Kitchen.visible_to(@user)

      def chosen
        return if @user.current_kitchen_id.nil?

        visible.find_by(id: @user.current_kitchen_id)
      end

      # A kitchen shared with you that is in use beats your own empty one —
      # the case where you opened Food before your partner shared theirs.
      def busiest = visible.order(updated_at: :desc, id: :asc).first
  end
end
