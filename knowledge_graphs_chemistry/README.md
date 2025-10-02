
# Knowledge Graphs for Chemistry

## Project Summary

[BioBricks-OKG](https://insilica.co/posts/biobricks-okg-nsf/) is an initiative to revolutionize access to chemical health and safety data by building an open, harmonized knowledge graph. Funded by the NSF Proto-OKN program, the project extends the BioBricks-AI platform to consolidate over 60 public health and cheminformatics databases into a single, interoperable graph. This enables quick, unified access to normalized chemical safety data, supporting developers, researchers, and AI tools in building applications and making informed decisions. By partnering with organizations like NICEATM, BioBricks-OKG aims to address challenges in toxicology and chemical safety, making diverse and complex data more accessible, consistent, and actionable. The project also explores the synergy between knowledge graphs and large language models (LLMs) to further enhance data utility and impact across health informatics.

## Project Plan

Had meeting today, collaborator from BioBricks-OKG will create a small demo with the following steps:

1. **Create empty Knowledge Graph database on Neptune**
2. **Spin up AWS instance** to create a demo Knowledge Graph
3. **Save it to S3**
4. **Tell Neptune to ingest it**
5. **Configure Neptune public API**
6. **Query public API with Python package**

I can start testing, documenting, and iterating on this process.

### Future Step

Later, we can add an additional step:

1. **Configure AWS Fargate** (Lambda for containers) to pull a pre-existing container to provide a web UI with SQL language as a frontend to Neptune

## Utilized AWS Services

- Amazon Neptune
- Amazon EC2 (for demo KG creation)
- Amazon S3
- AWS Fargate (future step)
- AWS Lambda (via Fargate)
