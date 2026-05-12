//! Istio interop client for tonic-xds.
//!
//! Builds an xDS channel against istiod, sends periodic gRPC unary calls to
//! the greeter service, and logs everything through `tracing_subscriber` so
//! tonic-xds's internal `tracing::warn!`/`tracing::error!` calls surface in
//! `kubectl logs`. Configure verbosity via `RUST_LOG` (e.g.
//! `RUST_LOG=info,tonic_xds=debug,xds_client=debug`).

use std::env;
use std::time::Duration;

use tonic_xds::testutil::proto::helloworld::{HelloRequest, greeter_client::GreeterClient};
use tonic_xds::{XdsChannelBuilder, XdsChannelConfig, XdsUri};
use tracing::{error, info};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .with_target(true)
        .init();

    let target_str = env::var("XDS_TARGET").unwrap_or_else(|_| "xds:///my-service".into());
    info!(target = %target_str, "building xDS channel");

    let target = XdsUri::parse(&target_str)?;
    let channel = XdsChannelBuilder::new(XdsChannelConfig::new(target)).build_grpc_channel()?;
    info!("channel built; sending requests every 5s");

    let mut client = GreeterClient::new(channel);

    for i in 1u64.. {
        let request = HelloRequest {
            name: format!("request-{i}"),
        };
        info!(request_num = i, "sending unary request");

        match client.say_hello(request).await {
            Ok(response) => {
                let msg = response.into_inner().message;
                info!(request_num = i, response = %msg, "request ok");
            }
            Err(status) => {
                let source = std::error::Error::source(&status).map(|e| e.to_string());
                error!(
                    request_num = i,
                    code = ?status.code(),
                    message = %status.message(),
                    ?source,
                    "request error",
                );
            }
        }

        tokio::time::sleep(Duration::from_secs(5)).await;
    }

    Ok(())
}
