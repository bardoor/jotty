defmodule Jotty.Soniox do
  @moduledoc """
  Owns the complete Soniox asynchronous transcription lifecycle.
  """

  @doc """
  Uploads an audio file, waits for speaker-diarized transcription, returns a
  readable transcript, and removes the remote file and transcription.
  """
  @spec transcribe(Path.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def transcribe(audio_path, api_key) do
    request = request(api_key)

    deadline =
      System.monotonic_time(:millisecond) + Application.fetch_env!(:jotty, :soniox_timeout)

    with {:ok, file_id} <- upload(request, audio_path),
         {:ok, transcription_id} <- create_transcription(request, file_id),
         :ok <- wait_until_completed(request, transcription_id, deadline),
         {:ok, tokens} <- fetch_transcript(request, transcription_id),
         :ok <- delete(request, "/v1/transcriptions/#{transcription_id}"),
         :ok <- delete(request, "/v1/files/#{file_id}") do
      {:ok, render_tokens(tokens)}
    end
  end

  defp request(api_key) do
    options =
      Keyword.merge(
        [
          base_url: "https://api.soniox.com",
          auth: {:bearer, api_key},
          receive_timeout: 60_000,
          retry: false
        ],
        Application.fetch_env!(:jotty, :soniox_req_options)
      )

    Req.new(options)
  end

  defp upload(request, audio_path) do
    file =
      {File.stream!(audio_path, 64_000, []), filename: Path.basename(audio_path), content_type: "audio/mp4"}

    result = Req.post(request, url: "/v1/files", form_multipart: [file: file])

    with {:ok, %{"id" => file_id}} <- response_body(result) do
      {:ok, file_id}
    end
  end

  defp create_transcription(request, file_id) do
    result =
      Req.post(request,
        url: "/v1/transcriptions",
        json: %{
          "enable_speaker_diarization" => true,
          "file_id" => file_id,
          "model" => "stt-async-v5"
        }
      )

    with {:ok, %{"id" => transcription_id}} <- response_body(result) do
      {:ok, transcription_id}
    end
  end

  defp wait_until_completed(request, transcription_id, deadline) do
    result = Req.get(request, url: "/v1/transcriptions/#{transcription_id}")
    response = response_body(result)

    handle_status(response, request, transcription_id, deadline)
  end

  defp handle_status({:ok, %{"status" => "completed"}}, _request, _id, _deadline), do: :ok

  defp handle_status(
         {:ok, %{"status" => "error", "error_message" => message}},
         _request,
         _id,
         _deadline
       ) do
    {:error, {:transcription, message}}
  end

  defp handle_status({:error, reason}, _request, _id, _deadline), do: {:error, reason}

  defp handle_status({:ok, %{"status" => _status}}, request, transcription_id, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :transcription_timeout}
    else
      Process.sleep(Application.fetch_env!(:jotty, :soniox_poll_interval))
      wait_until_completed(request, transcription_id, deadline)
    end
  end

  defp fetch_transcript(request, transcription_id) do
    result = Req.get(request, url: "/v1/transcriptions/#{transcription_id}/transcript")

    with {:ok, %{"tokens" => tokens}} <- response_body(result) do
      {:ok, tokens}
    end
  end

  defp delete(request, path) do
    result = Req.delete(request, url: path)

    with {:ok, _body} <- response_body(result) do
      :ok
    end
  end

  defp response_body({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp response_body({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:soniox_http, status, body}}
  end

  defp response_body({:error, exception}) do
    {:error, {:soniox_transport, exception}}
  end

  defp render_tokens(tokens) do
    tokens
    |> Enum.chunk_by(fn %{"speaker" => speaker} -> speaker end)
    |> Enum.map_join("\n\n", fn [%{"speaker" => speaker} | _] = speaker_tokens ->
      text = Enum.map_join(speaker_tokens, fn %{"text" => text} -> text end)
      "Speaker #{speaker}: #{String.trim(text)}"
    end)
  end
end
