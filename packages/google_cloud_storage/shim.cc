#include "shim.h"

#include <chrono>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <iostream>
#include <iterator>
#include <thread>
#include <utility>

#include "google/cloud/status.h"
#include "google/cloud/storage/bucket_metadata.h"
#include "google/cloud/storage/client.h"
#include "google/cloud/storage/object_metadata.h"
#include "google/cloud/storage/object_write_stream.h"

ShimClient createClient() {
  auto client = google::cloud::storage::Client::CreateDefaultClient();
  if (!client) {
    std::cerr << "Failed to create client: " << client.status() << "\n";
    return {nullptr};
  }
  return {new google::cloud::storage::Client(*std::move(client))};
}

void destroyClient(ShimClient client) {
  delete static_cast<google::cloud::storage::Client *>(client._client);
}

void uploadFile(ShimClient shim_client, const char *file_name,
                const char *bucket_name, const char *object_name,
                void (*callback)(ShimObjectMetadata metadata)) {
  auto client =
      static_cast<google::cloud::storage::Client *>(shim_client._client);

  std::string file_name_str(file_name);
  std::string bucket_name_str(bucket_name);
  std::string object_name_str(object_name);

  std::thread t(
      [client, file_name_str, bucket_name_str, object_name_str, callback]() {
        auto result =
            client->UploadFile(file_name_str, bucket_name_str, object_name_str);
        ShimObjectMetadata shim_metadata{nullptr, nullptr};
        if (result.ok()) {
          shim_metadata._metadata =
              new google::cloud::storage::ObjectMetadata(*std::move(result));
          std::cerr << "File uploaded: " << file_name_str << "\n";
        } else {
          shim_metadata._status =
              new google::cloud::Status(std::move(result.status()));
          std::cerr << "Failed to upload file: " << result.status() << "\n";
        }
        callback(shim_metadata);
      });
  t.detach();
}

void createBucket(ShimClient shim_client, const char *bucket_name,
                  const char *override_project_id, bool enable_object_retention,
                  const char *predefined_acl,
                  void (*callback)(ShimBucketMetadata metadata)) {
  auto client =
      static_cast<google::cloud::storage::Client *>(shim_client._client);

  std::string bucket_name_str(bucket_name);
  std::string override_project_id_str(override_project_id);
  std::string predefined_acl_str(predefined_acl);

  std::thread t([client, bucket_name_str, override_project_id_str,
                 predefined_acl_str, enable_object_retention, callback]() {
    // TODO(b/390684041): As passing GCS request options via
    // google::cloud::Options xis not supported, options passed to this function
    // are ignored.
    auto result = client->CreateBucket(
        bucket_name_str, google::cloud::storage::BucketMetadata());
    ShimBucketMetadata shim_metadata{nullptr, nullptr};
    if (result.ok()) {
      shim_metadata._metadata =
          new google::cloud::storage::BucketMetadata(*std::move(result));
      std::cerr << "Bucket created: " << bucket_name_str << "\n";
    } else {
      shim_metadata._status =
          new google::cloud::Status(std::move(result.status()));
      std::cerr << "Failed to create bucket: " << result.status().message()
                << "\n";
    }
    callback(shim_metadata);
  });
  t.detach();
}

ShimObjectWriteStream writeObject(ShimClient shim_client,
                                  const char *bucket_name,
                                  const char *object_name) {
  auto client =
      static_cast<google::cloud::storage::Client *>(shim_client._client);
  auto writer =
      client->WriteObject(std::string(bucket_name), std::string(object_name));
  return {new google::cloud::storage::ObjectWriteStream(std::move(writer))};
}

int writeChunk(ShimObjectWriteStream writer, const char *data, int size) {
  auto stream =
      static_cast<google::cloud::storage::ObjectWriteStream *>(writer._writer);
  stream->write(data, size);
  if (!stream->good()) {
    std::cerr << "Failed to write chunk: " << stream->last_status() << "\n";
    return 0; // Error
  }
  return 1; // Success
}

void destroyWriter(ShimObjectWriteStream writer) {
  delete static_cast<google::cloud::storage::ObjectWriteStream *>(
      writer._writer);
}

void getObjectMetadata(ShimClient shim_client, const char *bucket_name,
                       const char *object_name,
                       void (*callback)(ShimObjectMetadata metadata)) {
  auto client =
      static_cast<google::cloud::storage::Client *>(shim_client._client);

  std::string bucket_name_str(bucket_name);
  std::string object_name_str(object_name);

  std::thread t([client, bucket_name_str, object_name_str, callback]() {
    auto result = client->GetObjectMetadata(bucket_name_str, object_name_str);
    ShimObjectMetadata shim_metadata{nullptr, nullptr};
    if (result.ok()) {
      shim_metadata._metadata =
          new google::cloud::storage::ObjectMetadata(*std::move(result));
    } else {
      shim_metadata._status =
          new google::cloud::Status(std::move(result.status()));
    }
    callback(shim_metadata);
  });
  t.detach();
}

shim_bool shimObjectMetadataOk(ShimObjectMetadata metadata) {
  return metadata._status == nullptr;
}

const char *shimObjectMetadataName(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->name().c_str());
}

const char *shimObjectMetadataBucket(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->bucket().c_str());
}

shim_uint64_t shimObjectMetadataSize(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return meta->size();
}

const char *shimObjectMetadataContentType(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->content_type().c_str());
}

const char *shimObjectMetadataMd5Hash(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->md5_hash().c_str());
}

const char *shimObjectMetadataCrc32c(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->crc32c().c_str());
}

shim_int64_t shimObjectMetadataGeneration(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return meta->generation();
}

shim_int64_t shimObjectMetadataMetageneration(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return meta->metageneration();
}

const char *shimObjectMetadataStorageClass(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->storage_class().c_str());
}

shim_time_t shimObjectMetadataTimeCreated(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return std::chrono::system_clock::to_time_t(meta->time_created());
}

const char *shimObjectMetadataCacheControl(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->cache_control().c_str());
}

int shimObjectMetadataComponentCount(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return meta->component_count();
}

const char *shimObjectMetadataContentDisposition(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->content_disposition().c_str());
}

const char *shimObjectMetadataContentEncoding(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->content_encoding().c_str());
}

const char *shimObjectMetadataContentLanguage(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->content_language().c_str());
}

shim_time_t shimObjectMetadataCustomTime(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return std::chrono::system_clock::to_time_t(meta->custom_time());
}

const char *shimObjectMetadataETag(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->etag().c_str());
}

shim_bool shimObjectMetadataEventBasedHold(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return false;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return meta->event_based_hold();
}

const char *shimObjectMetadataId(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->id().c_str());
}

const char *shimObjectMetadataKmsKeyName(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->kms_key_name().c_str());
}

const char *shimObjectMetadataMediaLink(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->media_link().c_str());
}

shim_time_t
shimObjectMetadataRetentionExpirationTime(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return std::chrono::system_clock::to_time_t(
      meta->retention_expiration_time());
}

const char *shimObjectMetadataSelfLink(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->self_link().c_str());
}

shim_bool shimObjectMetadataTemporaryHold(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return false;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return meta->temporary_hold();
}

shim_time_t shimObjectMetadataTimeDeleted(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return std::chrono::system_clock::to_time_t(meta->time_deleted());
}

shim_time_t
shimObjectMetadataTimeStorageClassUpdated(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return std::chrono::system_clock::to_time_t(
      meta->time_storage_class_updated());
}

shim_time_t shimObjectMetadataUpdated(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return std::chrono::system_clock::to_time_t(meta->updated());
}

const char *shimObjectMetadataOwnerEntity(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  if (!meta->has_owner())
    return nullptr;
  return strdup(meta->owner().entity.c_str());
}

const char *shimObjectMetadataOwnerEntityId(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  if (!meta->has_owner())
    return nullptr;
  return strdup(meta->owner().entity_id.c_str());
}

shim_bool shimObjectMetadataHasRetention(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return false;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return meta->has_retention();
}

const char *shimObjectMetadataRetentionMode(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata ||
      !static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata)
           ->has_retention())
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return strdup(meta->retention().mode.c_str());
}

shim_time_t
shimObjectMetadataRetentionRetainUntilTime(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata ||
      !static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata)
           ->has_retention())
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return static_cast<shim_time_t>(std::chrono::system_clock::to_time_t(
      meta->retention().retain_until_time));
}

int shimObjectMetadataUserMetadataCount(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return meta->metadata().size();
}

const char *shimObjectMetadataUserMetadataKey(ShimObjectMetadata metadata,
                                              int index) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  const auto &map = meta->metadata();
  if (index < 0 || index >= map.size())
    return nullptr;
  auto it = map.begin();
  std::advance(it, index);
  return strdup(it->first.c_str());
}

const char *shimObjectMetadataUserMetadataValue(ShimObjectMetadata metadata,
                                                int index) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  const auto &map = meta->metadata();
  if (index < 0 || index >= map.size())
    return nullptr;
  auto it = map.begin();
  std::advance(it, index);
  return strdup(it->second.c_str());
}

int shimObjectMetadataAclCount(ShimObjectMetadata metadata) {
  if (metadata._status || !metadata._metadata)
    return 0;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  return meta->acl().size();
}

const char *shimObjectMetadataAclEntity(ShimObjectMetadata metadata,
                                        int index) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  const auto &acl = meta->acl();
  if (index < 0 || index >= acl.size())
    return nullptr;
  return strdup(acl[index].entity().c_str());
}

const char *shimObjectMetadataAclRole(ShimObjectMetadata metadata, int index) {
  if (metadata._status || !metadata._metadata)
    return nullptr;
  auto *meta =
      static_cast<google::cloud::storage::ObjectMetadata *>(metadata._metadata);
  const auto &acl = meta->acl();
  if (index < 0 || index >= acl.size())
    return nullptr;
  return strdup(acl[index].role().c_str());
}

void freeShimObjectMetadata(ShimObjectMetadata metadata) {
  if (metadata._status) {
    delete static_cast<google::cloud::Status *>(metadata._status);
  }
  if (metadata._metadata) {
    delete static_cast<google::cloud::storage::ObjectMetadata *>(
        metadata._metadata);
  }
}

void freeShimBucketMetadata(ShimBucketMetadata metadata) {
  if (metadata._status) {
    delete static_cast<google::cloud::Status *>(metadata._status);
  }
  if (metadata._metadata) {
    delete static_cast<google::cloud::storage::BucketMetadata *>(
        metadata._metadata);
  }
}
