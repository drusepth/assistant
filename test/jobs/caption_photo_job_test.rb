require "test_helper"

class CaptionPhotoJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @photo = users(:one).photos.create!(image: {
      io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg"
    })
    model_profiles(:smith).update!(vision: true)
  end

  test "captions the photo, suggests sections, and auto-files when untagged" do
    stub_llm(caption: "A summer afternoon in the park.", sections: [ "people", "not-a-real-slug" ])

    CaptionPhotoJob.perform_now(@photo)

    @photo.reload
    assert @photo.caption_captioned?
    assert_equal "A summer afternoon in the park.", @photo.caption
    assert_equal [ "people" ], @photo.suggested_sections
    assert_equal [ sections(:people) ], @photo.sections.to_a
  end

  test "hand-tagged photos keep their tags; suggestions stay suggestions" do
    @photo.sections << sections(:hobbies)
    stub_llm(caption: "A photo.", sections: [ "people" ])

    CaptionPhotoJob.perform_now(@photo)

    assert_equal [ sections(:hobbies) ], @photo.reload.sections.to_a
    assert_equal [ sections(:people) ], @photo.suggested_section_records
  end

  test "sends the stripped large variant as an inline image, never the original" do
    stub_llm(caption: "ok", sections: [])
    CaptionPhotoJob.perform_now(@photo)

    assert_requested(:post, ENDPOINT) do |request|
      image_part = JSON.parse(request.body)["messages"].last["content"]
        .find { |part| part["type"] == "image_url" }
      image_part["image_url"]["url"].start_with?("data:image/webp;base64,")
    end
  end

  test "without a vision-declared model the job is a quiet no-op" do
    model_profiles(:smith).update!(vision: false)

    CaptionPhotoJob.perform_now(@photo)
    assert_nil @photo.reload.caption_status
  end

  test "a permanent model error fails visibly on the photo" do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "bad key" } }.to_json)

    CaptionPhotoJob.perform_now(@photo)

    @photo.reload
    assert @photo.caption_failed?
    assert_match "401", @photo.caption_error
  end

  private
    def stub_llm(caption:, sections:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { caption: caption, sections: sections }.to_json } } ] }.to_json
      )
    end
end
