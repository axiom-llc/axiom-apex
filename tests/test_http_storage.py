"""APEX HTTP boundary and explicitly excluded local/legacy paths."""
import importlib.util
import json
import io
import os
from pathlib import Path
import select
import subprocess
import sys
from unittest.mock import patch

from apex.core.rag import store, pipeline
from apex.core.tools import _rag_multi_query_effect, RAG_MULTI_QUERY


def test_owner_handles_removed():
    assert not hasattr(store, '_get_client')
    assert not hasattr(store, '_get_collection')


def test_legacy_multi_query_unchanged(monkeypatch):
    monkeypatch.delenv('RAG_BASE_URL', raising=False)
    monkeypatch.delenv('RAG_API_TOKEN', raising=False)
    calls=[]
    def send(request, timeout):
        calls.append((request.full_url,json.loads(request.data),timeout))
        return io.BytesIO(b'{"answer":"next?","sources":["doc"]}')
    with patch('urllib.request.urlopen', side_effect=send):
        result=_rag_multi_query_effect({'question':'first'})
    assert calls==[('http://localhost:8000/query',{'question':'first'},60),
                   ('http://localhost:8000/query',{'question':'next?'},60)]
    assert result['sources']==['doc'] and not RAG_MULTI_QUERY.retry_safe


def test_evaluator_retains_local_store(monkeypatch):
    path=Path(__file__).resolve().parents[1]/'benchmarks/eval_rag.py'
    spec=importlib.util.spec_from_file_location('local_eval',path)
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    from rag import store as owner
    from apex.core.rag import embedder
    observed=[]
    def query(vector, cfg):
        observed.append(cfg)
        assert vector==[1.]
        return [{'metadata':{'doc_id':'legacy'}}]
    monkeypatch.setattr(embedder,'embed_query',lambda q,c:[1.])
    monkeypatch.setattr(owner,'query',query)
    monkeypatch.setattr(store,'query',lambda *a: (_ for _ in ()).throw(AssertionError('evaluator migrated')))
    assert module.retrieve('q',5,'~/.rag/chroma','documents','local-test-only')==['legacy']
    assert observed[0].collection_name=='documents' and observed[0].score_threshold==0.0
    # Parser defaults are retained independently of the explicit retrieve call.
    source=path.read_text()
    assert 'default="documents"' in source and 'default=os.path.expanduser("~/.rag/chroma")' in source


SERVER = r'''
from werkzeug.serving import make_server
from rag.config import load_config
from rag import store, embedder, generator
import server.app as api
api._config=load_config(gemini_api_key='server-test-only')
api._api_token=''
store._get_client(api._config.chroma_path)
embedder.embed_texts=lambda texts,c:[[1.]+[0.]*3071 for _ in texts]
embedder.embed_query=lambda q,c:[1.]+[0.]*3071
generator.generate_answer=lambda q,chunks,c:{'answer':c.generation_model,'sources':[],'chunk_count':len(chunks)}
server=make_server('127.0.0.1',0,api.app)
print(server.server_port,flush=True)
server.serve_forever()
'''
CALLER = r'''
import sys, importlib.abc
class Guard(importlib.abc.MetaPathFinder):
    def find_spec(self,name,*args):
        if name in ('rag.store','rag.pipeline','rag.persistence') or name.startswith('chromadb'):
            raise AssertionError('APEX opened owner: '+name)
sys.meta_path.insert(0,Guard())
from apex.core.rag import store, pipeline
from apex.core.rag.config import load_config
cfg=load_config(gemini_api_key='',score_threshold=-1)
assert not store.inspect(cfg)['exists']
store.create_collection(cfg)
assert pipeline.ingest('text',' /id ',cfg)['chunks_stored']==1
assert pipeline.query(' q ',cfg)['answer']=='gemini-3.5-flash-lite'
v=[1.]+[0.]*3071
assert store.upsert(['replacement'],[v],' /id ',cfg,{'valid':True}) is None
assert store.query(v,cfg)==pipeline.query(v,cfg)
assert store.query(v,cfg)[0]['text']=='replacement'
assert store.list_documents(cfg)==[' /id ']
assert store.collection_stats(cfg)=={'total_chunks':1,'documents':[' /id ']}
assert store.delete_document(' /id ',cfg)==1
assert not hasattr(store,'_get_client')
assert 'chromadb' not in sys.modules
'''


def test_separate_owner_apex(tmp_path):
    import rag
    env={k:v for k,v in os.environ.items() if not k.startswith('RAG_') and k!='GEMINI_API_KEY'}
    env.update(HOME=str(tmp_path), PYTHON_DOTENV_DISABLED='1',
               PYTHONPATH=os.pathsep.join([str(Path(__file__).resolve().parents[1]),str(Path(rag.__file__).resolve().parents[1])]))
    process=subprocess.Popen([sys.executable,'-c',SERVER],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        assert select.select([process.stdout],[],[],30)[0], 'owner startup timed out'
        port=process.stdout.readline().strip()
        assert port.isdigit(), process.stderr.read() if process.poll() is not None else 'owner failed startup'
        env['RAG_BASE_URL']='http://127.0.0.1:'+port
        result=subprocess.run([sys.executable,'-c',CALLER],env=env,capture_output=True,text=True,timeout=45)
        assert result.returncode==0,result.stderr
    finally:
        process.kill(); process.communicate(timeout=10)
