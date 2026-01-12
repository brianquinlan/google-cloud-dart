#include "shim.h"

#include "google/cloud/storage/client.h"
#include "google/cloud/storage/grpc_plugin.h"


#include <string>
#include <thread>

#include <iostream>

ShimClient createClient() {
    auto client = google::cloud::storage::Client::CreateDefaultClient();
    if (!client) {
        std::cerr << "Failed to create client: " << client.status() << "\n";
        return {nullptr};
    }
    return {new google::cloud::storage::Client(*std::move(client))};
}

void destroyClient(ShimClient client) {
    delete static_cast<google::cloud::storage::Client*>(client._client);
}

void _createBucket(google::cloud::storage::Client* client, std::string bucket_name, void (*callback)()) {
    auto status = client->CreateBucket(bucket_name, google::cloud::storage::BucketMetadata());
    if (!status.ok()) {
        std::cerr << "Failed to create bucket: " << status.status().message() << "\n";
    }
    std::cerr << "Bucket created: " << bucket_name << "\n";
    callback();
}

void createBucket(ShimClient shim_client, const char * bucket_name, void (*callback)()) {
    auto client = static_cast<google::cloud::storage::Client*>(shim_client._client);

    std::thread t2(_createBucket, client, std::string(bucket_name), callback);
    t2.detach();
}

ShimObjectWriteStream writeObject(ShimClient shim_client, const char * bucket_name, const char * object_name)
{
    auto client = static_cast<google::cloud::storage::Client*>(shim_client._client);
    auto writer = client->WriteObject(std::string(bucket_name), std::string(object_name));
    return {new google::cloud::storage::ObjectWriteStream(std::move(writer))};
}

int writeChunk(ShimObjectWriteStream writer, const char * data, int size) {
    auto stream = static_cast<google::cloud::storage::ObjectWriteStream*>(writer._writer);
    stream->write(data, size);
    if (!stream->good()) {
        std::cerr << "Failed to write chunk: " << stream->last_status() << "\n";
        return 0; // Error
    }
    return 1; // Success
}


void destroyWriter(ShimObjectWriteStream writer) {
    delete static_cast<google::cloud::storage::ObjectWriteStream*>(writer._writer);
}
