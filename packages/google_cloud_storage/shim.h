
typedef struct {
    void *_client;
} ShimClient;

typedef struct {
    void *_writer;
} ShimObjectWriteStream;

#ifdef __cplusplus
extern "C" {
#endif

   __attribute__((visibility("default"))) __attribute__((used)) ShimClient createClient();
   __attribute__((visibility("default"))) __attribute__((used)) void destroyClient(ShimClient client);

   __attribute__((visibility("default"))) __attribute__((used)) void createBucket(ShimClient shim_client, const char * bucket_name, void (*callback)());

   __attribute__((visibility("default"))) __attribute__((used)) ShimObjectWriteStream writeObject(ShimClient client, const char * bucket_name, const char * object_name);
   __attribute__((visibility("default"))) __attribute__((used)) int writeChunk(ShimObjectWriteStream writer, const char * data, int size);
   __attribute__((visibility("default"))) __attribute__((used)) void destroyWriter(ShimObjectWriteStream writer);
#ifdef __cplusplus
}
#endif