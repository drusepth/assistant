Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  get "setup" => "first_run#new", as: :setup
  post "setup" => "first_run#create"

  resources :invitations, only: %i[ create destroy ]
  get "join/:token" => "invitations#show", as: :join
  post "join/:token" => "invitations#accept"

  resources :household_members, only: %i[ update destroy ]

  root "dashboard#show"
  get "today" => "today#show", as: :today
  get "calendar(/:year/:month)" => "calendar#show", as: :calendar,
    constraints: { year: /\d{4}/, month: /\d{1,2}/ }
  get "sections/:slug" => "sections#show", as: :section

  resource :settings, only: %i[ show update ]
  resource :model_profile, only: %i[ update ]
  resources :access_grants, only: %i[ create destroy ]

  namespace :events do
    resource :import, only: %i[ new create ]
  end
  resources :events
  resources :tasks do
    member do
      patch :complete
      patch :reopen
      patch :reschedule
      patch :move
    end
  end
  resources :documents do
    member do
      post :analyze
      patch :apply_suggestion
    end
  end
  namespace :people do
    resource :import, only: %i[ new create ]
  end
  resources :people
  resources :goals do
    member do
      patch :complete
      patch :reopen
      post :break_down
    end
  end
  resources :notes

  get "tools/:tool_slug/run" => "tool_runs#new", as: :new_tool_run
  post "tools/:tool_slug/run" => "tool_runs#create", as: :run_tool
  resources :tool_runs, only: :show do
    resources :messages, only: :create, controller: "tool_run_messages"
    member do
      post :recap
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
