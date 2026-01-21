#ifndef EXPERIMENTAL_USERS_BQUINLAN_CPPCLIENT_SHIM_H_
#define EXPERIMENTAL_USERS_BQUINLAN_CPPCLIENT_SHIM_H_

#define VISIBLE __attribute__((visibility("default"))) __attribute__((used))

typedef long long shim_time_t;            // NOLINT
typedef unsigned long long shim_uint64_t; // NOLINT
typedef long long shim_int64_t;           // NOLINT
typedef int shim_bool;

#ifdef __cplusplus
extern "C" {
#endif

// Opaque struct representing a GCS client.
typedef struct {
  void *_client; // NOLINT
} ShimClient;

// Opaque struct representing a GCS object write stream.
typedef struct {
  void *_writer; // NOLINT
} ShimObjectWriteStream;

// Struct containing object metadata or status on error.
typedef struct {
  void *_status;   // NOLINT
  void *_metadata; // NOLINT
} ShimObjectMetadata;

// Struct containing bucket metadata or status on error.
typedef struct {
  void *_status;   // NOLINT
  void *_metadata; // NOLINT
} ShimBucketMetadata;

// Creates a GCS client with default options.
VISIBLE ShimClient createClient();

// Destroys a GCS client.
VISIBLE void destroyClient(ShimClient client);

// Uploads a file to GCS.
// This function is asynchronous and invokes the callback when complete.
VISIBLE void uploadFile(ShimClient shim_client, const char *file_name,
                        const char *bucket_name, const char *object_name,
                        void (*callback)(ShimObjectMetadata metadata));

// Creates a GCS bucket.
// This function is asynchronous and invokes the callback when complete.
VISIBLE void createBucket(ShimClient shim_client, const char *bucket_name,
                          const char *override_project_id,
                          shim_bool enable_object_retention,
                          const char *predefined_acl,
                          void (*callback)(ShimBucketMetadata metadata));

// Initiates a streaming write to a GCS object.
VISIBLE ShimObjectWriteStream writeObject(ShimClient shim_client,
                                          const char *bucket_name,
                                          const char *object_name);

// Writes a chunk of data to an object write stream.
// Returns 1 on success, 0 on failure.
VISIBLE int writeChunk(ShimObjectWriteStream writer, const char *data,
                       int size);

// Closes and destroys an object write stream.
VISIBLE void destroyWriter(ShimObjectWriteStream writer);

// Gets object metadata from GCS.
// This function is asynchronous and invokes the callback when complete.
VISIBLE void getObjectMetadata(ShimClient shim_client, const char *bucket_name,
                               const char *object_name,
                               void (*callback)(ShimObjectMetadata metadata));

// Returns true if the metadata represents a success status.
VISIBLE shim_bool shimObjectMetadataOk(ShimObjectMetadata metadata);

// Note: All functions returning 'const char*' allocate memory using strdup()
// and must be freed by the caller using free().

// Returns the object name from metadata. The returned string is valid as long
// as metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataName(ShimObjectMetadata metadata);

// Returns the bucket name from metadata. The returned string is valid as long
// as metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataBucket(ShimObjectMetadata metadata);

// Returns the object size from metadata. Returns 0 if metadata is from a
// failure.
VISIBLE shim_uint64_t shimObjectMetadataSize(ShimObjectMetadata metadata);

// Returns content type from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataContentType(ShimObjectMetadata metadata);

// Returns MD5 hash from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataMd5Hash(ShimObjectMetadata metadata);

// Returns CRC32C from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataCrc32c(ShimObjectMetadata metadata);

// Returns generation from metadata. Returns 0 if metadata is from a failure.
VISIBLE shim_int64_t shimObjectMetadataGeneration(ShimObjectMetadata metadata);

// Returns metageneration from metadata. Returns 0 if metadata is from a
// failure.
VISIBLE shim_int64_t
shimObjectMetadataMetageneration(ShimObjectMetadata metadata);

// Returns storage class from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataStorageClass(ShimObjectMetadata metadata);

// Returns time created from metadata. Returns 0 if metadata is from a failure.
VISIBLE shim_time_t shimObjectMetadataTimeCreated(ShimObjectMetadata metadata);

// Returns cache control from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataCacheControl(ShimObjectMetadata metadata);

// Returns component count from metadata. Returns 0 if metadata is from a
// failure.
VISIBLE int shimObjectMetadataComponentCount(ShimObjectMetadata metadata);

// Returns content disposition from metadata. The returned string is valid as
// long as metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *
shimObjectMetadataContentDisposition(ShimObjectMetadata metadata);

// Returns content encoding from metadata. The returned string is valid as long
// as metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *
shimObjectMetadataContentEncoding(ShimObjectMetadata metadata);

// Returns content language from metadata. The returned string is valid as long
// as metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *
shimObjectMetadataContentLanguage(ShimObjectMetadata metadata);

// Returns custom time from metadata. Returns 0 if metadata is from a failure.
VISIBLE shim_time_t shimObjectMetadataCustomTime(ShimObjectMetadata metadata);

// Returns ETag from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataETag(ShimObjectMetadata metadata);

// Returns event-based hold from metadata. Returns false if metadata is from a
// failure.
VISIBLE shim_bool shimObjectMetadataEventBasedHold(ShimObjectMetadata metadata);

// Returns ID from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataId(ShimObjectMetadata metadata);

// Returns KMS key name from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataKmsKeyName(ShimObjectMetadata metadata);

// Returns media link from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataMediaLink(ShimObjectMetadata metadata);

// Returns retention expiration time from metadata. Returns 0 if metadata is
// from a failure.
VISIBLE shim_time_t
shimObjectMetadataRetentionExpirationTime(ShimObjectMetadata metadata);

// Returns self link from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataSelfLink(ShimObjectMetadata metadata);

// Returns temporary hold from metadata. Returns false if metadata is from a
// failure.
VISIBLE shim_bool shimObjectMetadataTemporaryHold(ShimObjectMetadata metadata);

// Returns time deleted from metadata. Returns 0 if metadata is from a failure.
VISIBLE shim_time_t shimObjectMetadataTimeDeleted(ShimObjectMetadata metadata);

// Returns time storage class updated from metadata. Returns 0 if metadata is
// from a failure.
VISIBLE shim_time_t
shimObjectMetadataTimeStorageClassUpdated(ShimObjectMetadata metadata);

// Returns updated time from metadata. Returns 0 if metadata is from a failure.
VISIBLE shim_time_t shimObjectMetadataUpdated(ShimObjectMetadata metadata);

// Returns owner entity from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *shimObjectMetadataOwnerEntity(ShimObjectMetadata metadata);

// Returns owner entity ID from metadata. The returned string is valid as long
// as metadata is not freed. Returns NULL if metadata is from a failure.
VISIBLE const char *
shimObjectMetadataOwnerEntityId(ShimObjectMetadata metadata);

// Returns whether retention is set on metadata.
VISIBLE shim_bool shimObjectMetadataHasRetention(ShimObjectMetadata metadata);

// Returns retention mode from metadata. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure or
// retention is not set.
VISIBLE const char *
shimObjectMetadataRetentionMode(ShimObjectMetadata metadata);

// Returns retention retain-until-time from metadata. Returns 0 if metadata is
// from a failure or retention is not set.
VISIBLE shim_time_t
shimObjectMetadataRetentionRetainUntilTime(ShimObjectMetadata metadata);

// Returns user metadata count.
VISIBLE int shimObjectMetadataUserMetadataCount(ShimObjectMetadata metadata);

// Returns user metadata key by index. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure or index is
// out of bounds.
VISIBLE const char *
shimObjectMetadataUserMetadataKey(ShimObjectMetadata metadata, int index);

// Returns user metadata value by index. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure or index is
// out of bounds.
VISIBLE const char *
shimObjectMetadataUserMetadataValue(ShimObjectMetadata metadata, int index);

// Returns ACL count.
VISIBLE int shimObjectMetadataAclCount(ShimObjectMetadata metadata);

// Returns ACL entity by index. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure or index is
// out of bounds.
VISIBLE const char *shimObjectMetadataAclEntity(ShimObjectMetadata metadata,
                                                int index);

// Returns ACL role by index. The returned string is valid as long as
// metadata is not freed. Returns NULL if metadata is from a failure or index is
// out of bounds.
VISIBLE const char *shimObjectMetadataAclRole(ShimObjectMetadata metadata,
                                              int index);

// Frees memory associated with ShimObjectMetadata's members.
VISIBLE void freeShimObjectMetadata(ShimObjectMetadata metadata);

// Frees memory associated with ShimBucketMetadata's members.
VISIBLE void freeShimBucketMetadata(ShimBucketMetadata metadata);

#ifdef __cplusplus
}
#endif

#endif // EXPERIMENTAL_USERS_BQUINLAN_CPPCLIENT_SHIM_H_
