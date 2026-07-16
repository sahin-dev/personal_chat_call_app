const { MongoClient } = require('mongodb');

async function main() {
  const client = new MongoClient(
    'mongodb://127.0.0.1:27019/admin?directConnection=true',
    { serverSelectionTimeoutMS: 10000 },
  );

  await client.connect();
  try {
    await client.db('admin').command({
      replSetInitiate: {
        _id: 'rs0',
        members: [{ _id: 0, host: '127.0.0.1:27019' }],
      },
    });
    console.log('MongoDB replica set initiated on 127.0.0.1:27019');
  } catch (error) {
    if (String(error.message).includes('already initialized')) {
      console.log('MongoDB replica set already initialized on 127.0.0.1:27019');
    } else {
      throw error;
    }
  } finally {
    await client.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
