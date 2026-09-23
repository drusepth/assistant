require "test_helper"

class PetBreedGuessTest < ActionDispatch::IntegrationTest
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    sign_in_as users(:one)
    model_profiles(:smith).update!(vision: true)
    @rex = create_pet(species: "cat")
  end

  test "an uploaded photo comes back as suggestions to tap, and nothing is saved" do
    stub_llm(breeds: [ { name: "Maine Coon", likelihood: "likely" }, { name: "Norwegian Forest Cat", likelihood: "possible" } ],
      note: "Tufted ears and a long, shaggy coat.")

    assert_no_difference -> { Photo.count + ActiveStorage::Blob.count } do
      post breed_guess_path, params: { species: "cat", photo: upload }, as: :turbo_stream
    end
    assert_response :success
    assert_select "button[data-breed-guess-name-param=?]", "Maine Coon"
    assert_select "button[data-breed-guess-name-param=?]", "Norwegian Forest Cat", text: /maybe/
    assert_match "Tufted ears", response.body
    assert_nil @rex.reload.breed

    assert_requested(:post, ENDPOINT) do |request|
      content = JSON.parse(request.body)["messages"].last["content"]
      content.first["text"].include?("cat") &&
        content.find { |part| part["type"] == "image_url" }["image_url"]["url"].start_with?("data:image/webp;base64,")
    end
  end

  test "a photo already tagged with the pet is one tap" do
    photo = users(:one).photos.create!(image: upload)
    photo.sections << @rex.section
    stub_llm(breeds: [ { name: "Domestic shorthair", likelihood: "likely" } ], note: "")

    post breed_guess_path, params: { species: "cat", photo_id: photo.id }, as: :turbo_stream
    assert_select "button[data-breed-guess-name-param=?]", "Domestic shorthair"
  end

  test "someone else's photo can't be read by id" do
    photo = users(:two).photos.create!(image: upload)

    post breed_guess_path, params: { species: "cat", photo_id: photo.id }, as: :turbo_stream
    assert_match "Choose a photo first", response.body
    assert_not_requested :post, ENDPOINT
  end

  test "the model's answer is cleaned: blanks, duplicates and extras dropped" do
    stub_llm(breeds: [ { name: "Siamese" }, { name: "siamese" }, { name: "" }, "junk",
      { name: "Thai" }, { name: "Balinese" }, { name: "Tonkinese" } ], note: nil)

    post breed_guess_path, params: { species: "cat", photo: upload }, as: :turbo_stream
    names = css_select("button[data-breed-guess-name-param]").map { |button| button["data-breed-guess-name-param"] }
    assert_equal [ "Siamese", "Thai", "Balinese" ], names
  end

  test "no breed is an answer, said plainly" do
    stub_llm(breeds: [], note: "Only a tail is in frame.")

    post breed_guess_path, params: { species: "cat", photo: upload }, as: :turbo_stream
    assert_match "Only a tail is in frame.", response.body
    assert_select "button[data-breed-guess-name-param]", count: 0
  end

  test "a file that isn't an image is refused before the model sees it" do
    post breed_guess_path, params: { species: "cat", photo: fixture_file_upload("photo.jpg", "application/pdf") }, as: :turbo_stream
    assert_select ".field-error", text: /isn't a photo the app can read/
    assert_not_requested :post, ENDPOINT
  end

  test "without a vision model the form says what would turn the helper on" do
    model_profiles(:smith).update!(vision: false)

    get edit_pet_path(@rex)
    assert_match "a model that can see images", response.body
    assert_select "details[data-breed-guess-target=panel]", count: 0

    post breed_guess_path, params: { species: "cat", photo: upload }, as: :turbo_stream
    assert_select ".field-error", text: /needs a model that can see images/
  end

  test "the pet form offers the helper, with this pet's photos to tap" do
    @rex.avatar.attach(upload)

    get edit_pet_path(@rex)
    assert_select "details[data-breed-guess-target=panel]"
    assert_select "button[data-breed-guess-pet-id-param=?]", @rex.id.to_s

    get new_pet_path
    assert_select "details[data-breed-guess-target=panel]"
  end

  private
    def upload
      fixture_file_upload("photo.jpg", "image/jpeg")
    end

    def stub_llm(**fields)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: fields.to_json } } ] }.to_json
      )
    end
end
