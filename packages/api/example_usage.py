from api_framework import APIClient

if __name__ == "__main__":
    # Example against JSONPlaceholder (public API, no key required)
    with APIClient(
        base_url="https://jsonplaceholder.typicode.com",
        requests_per_second=5,
        max_retries=4,
        backoff_factor=1.0,
    ) as client:

        # GET
        posts = client.get("/posts", params={"userId": 1})
        print(f"Fetched {len(posts)} posts")

        # POST (returns mock response)
        new_post = client.post("/posts", json={
            "title": "Test",
            "body": "Framework demo",
            "userId": 1
        })
        print(f"Created post ID: {new_post['id']}")
