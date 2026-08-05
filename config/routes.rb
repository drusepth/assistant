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
  resources :access_grants, only: %i[ create destroy ]

  resources :events
  resources :tasks do
    member do
      patch :complete
      patch :reopen
    end
  end
  resources :documents
  resources :people
  resources :goals do
    member do
      patch :move
    end
  end
  resources :notes

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
