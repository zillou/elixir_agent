defmodule NewRelic.Telemetry.Finch do
  use GenServer

  # @finch_request_stop [:finch, :request, :stop]
  @finch_response_stop [:finch, :response, :stop]

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :telemetry.attach_many(
      {:new_relic, :finch},
      [@finch_response_stop],
      &__MODULE__.handle_event/4,
      %{}
    )

    Process.flag(:trap_exit, true)
    {:ok, []}
  end

  @component "Finch"
  def handle_event(
        @finch_response_stop,
        %{duration: duration},
        %{host: host, method: method} = meta,
        _config
      ) do
    end_time_ms = System.system_time(:millisecond)
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    duration_s = duration_ms / 1000
    start_time_ms = end_time_ms - duration_ms

    pid = inspect(self())
    id = {:finch, make_ref()}
    parent_id = Process.get(:nr_current_span) || :root

    metric_name = "External/#{host}/#{@component}/#{method}"
    secondary_name = "#{host} - #{@component}/#{method}"

    url = build_url(meta)

    NewRelic.Transaction.Reporter.add_trace_segment(%{
      primary_name: metric_name,
      secondary_name: secondary_name,
      attributes: %{},
      pid: pid,
      id: id,
      parent_id: parent_id,
      start_time: start_time_ms,
      end_time: end_time_ms
    })

    NewRelic.report_span(
      timestamp_ms: start_time_ms,
      duration_s: duration_s,
      name: metric_name,
      edge: [span: id, parent: parent_id],
      category: "http",
      attributes: %{
        component: @component
      }
    )

    NewRelic.incr_attributes(
      "external.#{host}.call_count": 1,
      "external.#{host}.duration_ms": duration_ms,
      externalCallCount: 1,
      externalDuration: duration_s,
      external_call_count: 1,
      external_duration_ms: duration_ms
    )

    NewRelic.report_metric({:external, url, @component, method}, duration_s: duration_s)

    NewRelic.Transaction.Reporter.track_metric({
      {:external, url, @component, method},
      duration_s: duration_s
    })

    NewRelic.Transaction.Reporter.track_metric({:external, duration_s})
  end

  def handle_event(_event, _measurements, _meta, _config) do
    :ignore
  end

  defp build_url(%{host: host, path: path, scheme: scheme, port: port}) do
    %URI{
      scheme: to_string(scheme),
      host: host,
      port: port,
      path: path
    }
    |> URI.to_string()
  end
end
