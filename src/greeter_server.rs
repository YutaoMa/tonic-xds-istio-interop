//! Minimal helloworld greeter server for the interop harness.
//!
//! Listens on `PORT` (default 50051), serves the `Greeter.SayHello` RPC. The
//! response embeds `SERVER_NAME` (default the pod hostname) so the client can
//! observe load-balancing across replicas.

use std::env;
use std::net::SocketAddr;

use tonic::transport::Server;
use tonic::{Request, Response, Status};
use tonic_xds::testutil::proto::helloworld::greeter_server::{Greeter, GreeterServer};
use tonic_xds::testutil::proto::helloworld::{HelloReply, HelloRequest};

#[derive(Default)]
struct GreeterImpl {
    server_name: String,
}

#[tonic::async_trait]
impl Greeter for GreeterImpl {
    async fn say_hello(
        &self,
        request: Request<HelloRequest>,
    ) -> Result<Response<HelloReply>, Status> {
        let name = request.into_inner().name;
        let reply = HelloReply {
            message: format!("{}: Hello, {}", self.server_name, name),
        };
        Ok(Response::new(reply))
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(50051);
    let addr: SocketAddr = format!("0.0.0.0:{port}").parse()?;

    let server_name = env::var("SERVER_NAME")
        .or_else(|_| env::var("HOSTNAME"))
        .unwrap_or_else(|_| "greeter".into());

    println!("greeter '{server_name}' listening on {addr}");

    Server::builder()
        .add_service(GreeterServer::new(GreeterImpl { server_name }))
        .serve(addr)
        .await?;

    Ok(())
}
