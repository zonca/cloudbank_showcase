
# Tutorial: Creating S3 Access Keys and Configuring AWS CLI

This guide will walk you through creating AWS access keys for S3 read/write and configuring your local environment using `aws configure`.

---

## 1. Create an IAM User with S3 Permissions

1. Log in to the [AWS Management Console](https://console.aws.amazon.com/).
2. Navigate to **IAM** (Identity and Access Management).
3. In the sidebar, click **Users** > **Create user**.
4. Enter a username (e.g., `s3-access-user`).
5. Click **Next: Permissions**.
6. Attach existing policies directly. For S3 read/write, search for and select:
	- `AmazonS3FullAccess` (or create a custom policy for more restricted access).
7. Click **Create user**.
8. Click on the user just created.
9. Under **Security credentials**, click **Create access key** > **Command Line Interface**.
10. Save the **Access Key ID** and **Secret Access Key**. **You will not be able to see the secret again!**
	- **Important:** Make sure you are not committing these credentials to a git repository.

---

## 2. Configure AWS CLI with Your Access Keys

Run the following command in your terminal:

```bash
aws configure
```

You will be prompted for:

1. **AWS Access Key ID**: Paste the key you copied earlier.
2. **AWS Secret Access Key**: Paste the secret you copied earlier.
3. **Default region name**: e.g., `us-west-2` (choose the region where your S3 bucket is located).
4. **Default output format**: e.g., `json` (or leave blank).

Your credentials will be saved in `~/.aws/credentials` and configuration in `~/.aws/config`.

---

## 3. Test Your Configuration

List your S3 buckets to verify access:

```bash
aws s3 ls
```

You should see a list of your S3 buckets. If you get a permissions error, check your IAM user permissions.

---

> **Security Note:**
>
> Never share your AWS secret access key. Rotate keys regularly and use IAM policies with the least privilege required.
